import Foundation
import SQLite3

/// 汇总所有来源。全部只读：不改任何应用的配置，也不读取任务 prompt 正文
enum Collector {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static func collectAll() -> [SourceReport] {
        [
            ClaudeCollector.collect(.claudeCode),
            ClaudeCollector.collect(.claudeCowork),
            CodexCollector.collect(),
            CursorCollector.collect(),
            LaunchdCollector.collect(),
            CronCollector.collect(),
        ]
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func parseISO(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}

// MARK: - Claude 桌面端（Code 定时任务 / Cowork 定时任务）

enum ClaudeCollector {
    static func collect(_ source: JobSource) -> SourceReport {
        let support = Collector.home.appendingPathComponent("Library/Application Support/Claude")
        guard FileManager.default.fileExists(atPath: support.path) else {
            return SourceReport(source: source, available: false, note: "未安装 Claude 桌面端", jobs: [])
        }
        let folder = source == .claudeCode ? "claude-code-sessions" : "local-agent-mode-sessions"
        var jobs: [ScheduledJob] = []
        var failed = 0
        for file in scheduleFiles(under: support.appendingPathComponent(folder)) {
            if let parsed = try? parse(file, source: source) {
                jobs += parsed
            } else {
                failed += 1
            }
        }
        let note: String?
        if failed > 0 {
            note = "有 \(failed) 个任务文件读取失败"
        } else {
            note = jobs.isEmpty ? "暂无定时任务" : nil
        }
        return SourceReport(source: source, available: true, note: note, jobs: jobs)
    }

    /// 结构为 <base>/<账号>/<组织>/scheduled-tasks.json，两层目录名是 UUID，不写死
    static func scheduleFiles(under base: URL) -> [URL] {
        let fm = FileManager.default
        guard let level1 = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return []
        }
        var out: [URL] = []
        for a in level1 {
            guard let level2 = try? fm.contentsOfDirectory(at: a, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
                continue
            }
            for b in level2 {
                let f = b.appendingPathComponent("scheduled-tasks.json")
                if fm.fileExists(atPath: f.path) { out.append(f) }
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    static func parse(_ file: URL, source: JobSource) throws -> [ScheduledJob] {
        let data = try Data(contentsOf: file)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let tasks = root["scheduledTasks"] as? [[String: Any]] ?? []
        let scope = file.deletingLastPathComponent().lastPathComponent
        return tasks.compactMap { t -> ScheduledJob? in
            guard let id = t["id"] as? String else { return nil }
            let enabled = t["enabled"] as? Bool ?? false
            let lastRun = (t["lastRunAt"] as? String).flatMap(Collector.parseISO)

            let info: ScheduleInfo
            let raw: String
            if let cron = t["cronExpression"] as? String, !cron.isEmpty {
                info = ScheduleText.cron(cron)
                raw = "cron: \(cron)"
            } else if let fire = (t["fireAt"] as? NSNumber)?.doubleValue {
                let date = Date(timeIntervalSince1970: fire / 1000)
                info = ScheduleText.once(date)
                raw = "fireAt: \(RelativeTime.full(date))"
            } else {
                info = ScheduleInfo(text: "未知调度", period: nil, oneShot: false)
                raw = ""
            }

            let status: JobStatus
            if enabled {
                status = .active
            } else {
                status = info.oneShot && lastRun != nil ? .finished : .paused
            }
            let display = (t["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let cwd = (t["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return ScheduledJob(
                id: "\(source.rawValue):\(scope):\(id)",
                source: source,
                name: display ?? id,
                schedule: info.text,
                rawSchedule: raw,
                status: status,
                lastActivity: lastRun,
                lastActivityLabel: "上次运行",
                detail: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
                tag: nil,
                issue: nil,
                filePath: t["filePath"] as? String,
                periodSeconds: info.period
            )
        }
    }
}

// MARK: - Codex automations

enum CodexCollector {
    static func collect() -> SourceReport {
        let fm = FileManager.default
        let codexHome = Collector.home.appendingPathComponent(".codex")
        guard fm.fileExists(atPath: codexHome.path) else {
            return SourceReport(source: .codex, available: false, note: "未安装 Codex", jobs: [])
        }
        // 只取 automations/ 的直接子目录；旁边的 automations-backup-* 不算
        let base = codexHome.appendingPathComponent("automations")
        let dirs = ((try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var parsed: [(file: URL, kv: [String: TOMLValue])] = []
        var failed = 0
        for dir in dirs {
            let file = dir.appendingPathComponent("automation.toml")
            guard fm.fileExists(atPath: file.path) else { continue }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                failed += 1
                continue
            }
            let kv = TOMLLite.parseTopLevel(text, skipKeys: ["prompt"])
            guard kv["id"]?.string != nil else {
                failed += 1
                continue
            }
            parsed.append((file, kv))
        }

        let threadIDs = parsed.compactMap { $0.kv["target_thread_id"]?.string }
        let runs = CodexRunIndex.load(codexHome: codexHome, threadIDs: threadIDs)

        let jobs = parsed.map { item -> ScheduledJob in
            let kv = item.kv
            let id = kv["id"]?.string ?? item.file.deletingLastPathComponent().lastPathComponent
            let kind = kv["kind"]?.string ?? "cron"
            let rrule = kv["rrule"]?.string ?? ""
            let info = rrule.isEmpty ? ScheduleInfo(text: "未知调度", period: nil, oneShot: false) : ScheduleText.rrule(rrule)

            // cron 类每次运行新建线程，取最近一次；heartbeat 类在既有线程里追加，只能看线程最近活动
            let lastActivity: Date?
            let label: String
            if kind == "heartbeat" {
                lastActivity = kv["target_thread_id"]?.string.flatMap { runs.threadActivity[$0] }
                label = "线程活动"
            } else {
                lastActivity = runs.lastRun[id]
                label = "上次运行"
            }

            let statusRaw = (kv["status"]?.string ?? "").uppercased()
            var status: JobStatus = statusRaw == "ACTIVE" ? .active : .paused
            if info.oneShot, kind != "heartbeat", lastActivity != nil { status = .finished }

            let cwd = kv["cwds"]?.strings?.first
            return ScheduledJob(
                id: "codex:\(id)",
                source: .codex,
                name: kv["name"]?.string ?? id,
                schedule: info.text,
                rawSchedule: rrule,
                status: status,
                lastActivity: lastActivity,
                lastActivityLabel: label,
                detail: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
                tag: kind == "heartbeat" ? "心跳" : nil,
                issue: statusRaw.isEmpty || statusRaw == "ACTIVE" || statusRaw == "PAUSED" ? nil : "状态 \(statusRaw)",
                filePath: item.file.path,
                periodSeconds: info.period
            )
        }

        let note: String?
        if failed > 0 {
            note = "有 \(failed) 个 automation 读取失败"
        } else if let error = runs.error {
            note = error
        } else {
            note = jobs.isEmpty ? "暂无 automation" : nil
        }
        return SourceReport(source: .codex, available: true, note: note, jobs: jobs)
    }
}

/// 从 Codex 的线程库读取运行记录（只读打开，库由 Codex 以 WAL 模式写入）
struct CodexRunIndex {
    var lastRun: [String: Date] = [:]
    var threadActivity: [String: Date] = [:]
    /// 运行记录读不到时的原因，显示在来源的提示里
    var error: String?

    static func load(codexHome: URL, threadIDs: [String]) -> CodexRunIndex {
        var index = CodexRunIndex()
        guard let dbPath = latestStateDB(in: codexHome) else {
            index.error = "未找到 Codex 运行记录库，上次运行时间不可用"
            return index
        }
        guard let db = openReadOnly(dbPath) else {
            index.error = "Codex 运行记录库打开失败，上次运行时间不可用"
            return index
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT substr(title, 1, 400), created_at_ms FROM threads WHERE thread_source = 'automation'"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let text = sqlite3_column_text(stmt, 0) else { continue }
                let ms = sqlite3_column_int64(stmt, 1)
                guard ms > 0, let id = automationID(fromTitle: String(cString: text)) else { continue }
                let date = Date(timeIntervalSince1970: Double(ms) / 1000)
                if date > index.lastRun[id] ?? .distantPast { index.lastRun[id] = date }
            }
        } else {
            index.error = "Codex 运行记录读取失败（\(String(cString: sqlite3_errmsg(db)))），上次运行时间不可用"
        }
        sqlite3_finalize(stmt)

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for tid in Set(threadIDs) {
            var q: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT updated_at_ms FROM threads WHERE id = ?", -1, &q, nil) == SQLITE_OK else {
                sqlite3_finalize(q)
                continue
            }
            sqlite3_bind_text(q, 1, tid, -1, transient)
            if sqlite3_step(q) == SQLITE_ROW {
                let ms = sqlite3_column_int64(q, 0)
                if ms > 0 { index.threadActivity[tid] = Date(timeIntervalSince1970: Double(ms) / 1000) }
            }
            sqlite3_finalize(q)
        }
        return index
    }

    /// 只读打开 Codex 的线程库。
    /// 库是 WAL 模式：Codex 关掉所有连接后 -wal/-shm 会被删掉，此时只读连接建不了 -shm，查询报 SQLITE_CANTOPEN。
    /// 没有 -wal 说明没有未写回主库的数据，改用 immutable=1 直接读主库文件。
    /// 不用读写方式打开：读写连接关闭时会做 checkpoint，等于改写了 Codex 的库。
    static func openReadOnly(_ path: String) -> OpaquePointer? {
        let walExists = FileManager.default.fileExists(atPath: path + "-wal")
        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            sqlite3_busy_timeout(db, 1500)
            let rc = sqlite3_exec(db, "SELECT 1 FROM sqlite_master LIMIT 1", nil, nil, nil)
            // 其它错误交给后面的查询报出具体原因
            if rc != SQLITE_CANTOPEN || walExists { return db }
        }
        sqlite3_close(db)
        db = nil
        // 有 -wal 时主库文件可能缺最新数据，不能用 immutable 读
        guard !walExists else { return nil }
        let uri = URL(fileURLWithPath: path).absoluteString + "?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    /// 自动化线程标题形如 "Automation: 名称\nAutomation ID: xxx\n..."
    static func automationID(fromTitle title: String) -> String? {
        let prefix = "Automation ID: "
        for line in title.split(separator: "\n") where line.hasPrefix(prefix) {
            let id = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : id
        }
        return nil
    }

    /// state_<N>.sqlite 取 N 最大的那个（Codex 升级库结构时会递增）
    static func latestStateDB(in dir: URL) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let best = names.compactMap { name -> (Int, String)? in
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                  let n = Int(name.dropFirst(6).dropLast(7)) else { return nil }
            return (n, name)
        }.max { $0.0 < $1.0 }
        return best.map { dir.appendingPathComponent($0.1).path }
    }
}

// MARK: - Cursor

enum CursorCollector {
    /// Cursor 目前没有本机定时任务的存储，这里只如实报告是否安装
    static func collect() -> SourceReport {
        let fm = FileManager.default
        let installed = fm.fileExists(atPath: "/Applications/Cursor.app")
            || fm.fileExists(atPath: Collector.home.appendingPathComponent(".cursor").path)
        return SourceReport(
            source: .cursor,
            available: installed,
            note: installed ? "本机未发现 Cursor 定时任务数据" : "未安装 Cursor",
            jobs: []
        )
    }
}

// MARK: - launchd（只收按时间触发的 plist）

enum LaunchdCollector {
    /// 厂商自带的定时项不算
    static let vendorPrefixes = [
        "com.apple.", "com.google.", "com.microsoft.", "com.adobe.", "homebrew.", "com.epicgames.",
        "com.moonshot.", "com.piriform.", "com.teamviewer.", "us.zoom.", "com.docker.", "com.cloudflare.",
        "org.openvpn.", "org.wireshark.", "com.oracle.", "com.sogou.", "com.netease.", "at.obdev.",
        "com.xk72.", "com.tw93.", "com.crystalidea.", "com.pvpn.", "com.jetbrains.", "com.dropbox.",
        "com.spotify.", "com.openai.", "com.anthropic.", "com.tencent.", "com.alibaba.", "com.bytedance.",
    ]

    static func collect() -> SourceReport {
        // nil 表示 launchctl 读取失败：加载状态未知，而不是全部未加载
        let userJobs = loadedUserJobs()
        let dirs: [(path: String, isDaemon: Bool)] = [
            (Collector.home.appendingPathComponent("Library/LaunchAgents").path, false),
            ("/Library/LaunchAgents", false),
            ("/Library/LaunchDaemons", true),
        ]
        var jobs: [ScheduledJob] = []
        for dir in dirs {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { $0.hasSuffix(".plist") }
                .sorted()
            for name in names {
                let path = (dir.path as NSString).appendingPathComponent(name)
                guard let data = FileManager.default.contents(atPath: path),
                      let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
                else { continue }
                let label = plist["Label"] as? String ?? (name as NSString).deletingPathExtension
                if vendorPrefixes.contains(where: { label.hasPrefix($0) }) { continue }
                guard let info = schedule(plist) else { continue }

                let disabled = plist["Disabled"] as? Bool ?? false
                let loaded: Bool
                var exitCode: Int?
                if dir.isDaemon {
                    loaded = systemJobLoaded(label)
                } else if let userJobs {
                    exitCode = userJobs[label]
                    loaded = exitCode != nil
                } else {
                    loaded = true
                }

                let logPath = (plist["StandardOutPath"] as? String) ?? (plist["StandardErrorPath"] as? String)
                var issue: String?
                if let code = exitCode, code != 0 { issue = "上次退出码 \(code)" }
                if !loaded, !disabled { issue = "未加载" }
                if userJobs == nil, !dir.isDaemon { issue = "加载状态未知" }

                var detail = programName(plist, fallback: label)
                if dir.isDaemon { detail += " · root" }

                jobs.append(ScheduledJob(
                    id: "launchd:\(path)",
                    source: .launchd,
                    name: label,
                    schedule: info.text,
                    rawSchedule: rawSchedule(plist),
                    status: loaded && !disabled ? .active : .paused,
                    lastActivity: logPath.flatMap(Collector.modificationDate),
                    lastActivityLabel: "日志更新",
                    detail: detail,
                    tag: nil,
                    issue: issue,
                    filePath: path,
                    periodSeconds: info.period
                ))
            }
        }
        let note: String?
        if userJobs == nil {
            note = "launchctl 读取失败，加载状态未知"
        } else {
            note = jobs.isEmpty ? "暂无定时 plist" : nil
        }
        return SourceReport(source: .launchd, available: true, note: note, jobs: jobs)
    }

    static func schedule(_ plist: [String: Any]) -> ScheduleInfo? {
        if let seconds = (plist["StartInterval"] as? NSNumber)?.intValue, seconds > 0 {
            return ScheduleText.launchdInterval(seconds)
        }
        if let dict = plist["StartCalendarInterval"] as? [String: Any] {
            return ScheduleText.launchd(calendar: dict)
        }
        if let list = plist["StartCalendarInterval"] as? [[String: Any]], !list.isEmpty {
            return ScheduleText.launchd(calendars: list)
        }
        return nil
    }

    static func rawSchedule(_ plist: [String: Any]) -> String {
        if let seconds = (plist["StartInterval"] as? NSNumber)?.intValue { return "StartInterval: \(seconds)" }
        if let value = plist["StartCalendarInterval"] { return "StartCalendarInterval: \(value)" }
        return ""
    }

    /// 只显示脚本/程序的文件名，不显示完整参数（参数里可能带密钥）
    static func programName(_ plist: [String: Any], fallback: String) -> String {
        let args = plist["ProgramArguments"] as? [String] ?? (plist["Program"] as? String).map { [$0] } ?? []
        let interpreters: Set<String> = ["bash", "zsh", "sh", "env", "node", "ruby", "perl", "osascript", "caffeinate"]
        for arg in args {
            if arg.hasPrefix("-") { continue }
            // 路径本身可能含空格（如 Application Support），以文件是否存在区分路径和内联命令
            let isFile = arg.hasPrefix("/") && FileManager.default.fileExists(atPath: arg)
            if !isFile, arg.contains(" ") || arg.contains("\n") { return "内联脚本" }
            let base = (arg as NSString).lastPathComponent
            if interpreters.contains(base) || base.hasPrefix("python") { continue }
            return base
        }
        return args.first.map { ($0 as NSString).lastPathComponent } ?? fallback
    }

    /// `launchctl list` → [label: 上次退出码]；读取失败返回 nil
    static func loadedUserJobs() -> [String: Int]? {
        guard let r = Shell.run("/bin/launchctl", ["list"]), r.status == 0 else { return nil }
        var out: [String: Int] = [:]
        for line in r.output.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            out[String(cols[2])] = Int(cols[1]) ?? 0
        }
        return out
    }

    static func systemJobLoaded(_ label: String) -> Bool {
        Shell.run("/bin/launchctl", ["print", "system/\(label)"])?.status == 0
    }
}

// MARK: - crontab

enum CronCollector {
    static func collect() -> SourceReport {
        guard let r = Shell.run("/usr/bin/crontab", ["-l"]) else {
            return SourceReport(source: .cron, available: true, note: "读取 crontab 失败", jobs: [])
        }
        // 没有 crontab 时 crontab -l 返回非 0
        guard r.status == 0 else {
            return SourceReport(source: .cron, available: true, note: "暂无 crontab", jobs: [])
        }
        let jobs = parse(r.output)
        return SourceReport(source: .cron, available: true, note: jobs.isEmpty ? "暂无 crontab" : nil, jobs: jobs)
    }

    static func parse(_ text: String) -> [ScheduledJob] {
        var jobs: [ScheduledJob] = []
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.range(of: #"^[A-Za-z_][A-Za-z0-9_]*\s*="#, options: .regularExpression) != nil { continue }

            let expr: String
            let command: String
            if line.hasPrefix("@") {
                let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count == 2 else { continue }
                expr = String(parts[0])
                command = String(parts[1])
            } else {
                let parts = line.split(maxSplits: 5, whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count == 6 else { continue }
                expr = parts[0..<5].joined(separator: " ")
                command = String(parts[5])
            }
            let info = ScheduleText.cron(expr)

            var name: String?
            if let hash = command.range(of: " # ", options: .backwards), !insideQuotes(command[..<hash.lowerBound]) {
                let comment = command[hash.upperBound...].trimmingCharacters(in: .whitespaces)
                if !comment.isEmpty { name = comment }
            }

            var logDate: Date?
            if let m = command.range(of: #">>?\s*(/[^\s;&|]+)"#, options: .regularExpression) {
                let path = command[m].drop(while: { $0 == ">" || $0.isWhitespace })
                logDate = Collector.modificationDate(String(path))
            }

            jobs.append(ScheduledJob(
                id: "cron:\(index)",
                source: .cron,
                name: name ?? commandName(command),
                schedule: info.text,
                rawSchedule: expr,
                status: .active,
                lastActivity: logDate,
                lastActivityLabel: "日志更新",
                detail: workingDir(command),
                tag: nil,
                issue: nil,
                filePath: nil,
                periodSeconds: info.period
            ))
        }
        return jobs
    }

    /// 前缀里单/双引号没有闭合，说明后面的 # 在引号内，不是注释
    static func insideQuotes(_ prefix: Substring) -> Bool {
        prefix.filter { $0 == "\"" }.count % 2 == 1 || prefix.filter { $0 == "'" }.count % 2 == 1
    }

    /// "cd /a/b && ..." → "b"
    static func workingDir(_ command: String) -> String? {
        guard command.hasPrefix("cd "),
              let dir = command.dropFirst(3).split(whereSeparator: { $0 == " " || $0 == "&" || $0 == ";" }).first
        else { return nil }
        return (String(dir) as NSString).lastPathComponent
    }

    /// 只取第一个可执行文件的名字，不显示完整命令
    static func commandName(_ command: String) -> String {
        var rest = Substring(command)
        if command.hasPrefix("cd "), let amp = command.range(of: "&&") {
            rest = command[amp.upperBound...]
        }
        for token in rest.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            if token.contains("=") { continue }
            return (String(token) as NSString).lastPathComponent
        }
        return "cron 任务"
    }
}

// MARK: - 子进程

enum Shell {
    /// 运行命令并取 stdout；超时返回 nil
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 5) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let box = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: box.data, as: UTF8.self))
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }
}
