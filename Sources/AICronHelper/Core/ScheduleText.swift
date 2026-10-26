import Foundation

struct ScheduleInfo {
    let text: String
    /// 大致触发间隔（秒）
    let period: Double?
    let oneShot: Bool
}

/// 把 cron / RRULE / launchd 调度翻译成中文短句。只做描述，不计算下次触发时间
enum ScheduleText {
    private static let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    static func hhmm(_ h: Int, _ m: Int) -> String { String(format: "%02d:%02d", h, m) }

    // MARK: - cron

    static func cron(_ expr: String) -> ScheduleInfo {
        let trimmed = expr.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("@") { return macro(trimmed) }
        let f = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard f.count >= 5 else { return ScheduleInfo(text: "cron \(trimmed)", period: nil, oneShot: false) }
        return describe(minute: f[0], hour: f[1], dom: f[2], month: f[3], dow: f[4])
            ?? ScheduleInfo(text: "cron \(trimmed)", period: nil, oneShot: false)
    }

    static func macro(_ m: String) -> ScheduleInfo {
        switch m {
        case "@hourly": return .init(text: "每小时", period: 3600, oneShot: false)
        case "@daily", "@midnight": return .init(text: "每天 00:00", period: 86400, oneShot: false)
        case "@weekly": return .init(text: "每周日 00:00", period: 604_800, oneShot: false)
        case "@monthly": return .init(text: "每月 1 日 00:00", period: 2_592_000, oneShot: false)
        case "@yearly", "@annually": return .init(text: "每年 1 月 1 日", period: 31_536_000, oneShot: false)
        case "@reboot": return .init(text: "开机时运行", period: nil, oneShot: false)
        default: return .init(text: m, period: nil, oneShot: false)
        }
    }

    /// "5"、"1,3,5"、"1-5" → 整数列表；含 * 或步长时返回 nil
    static func ints(_ field: String) -> [Int]? {
        var out: [Int] = []
        for part in field.split(separator: ",") {
            if let dash = part.firstIndex(of: "-") {
                guard let a = Int(part[..<dash]), let b = Int(part[part.index(after: dash)...]), a <= b else { return nil }
                out.append(contentsOf: a...b)
            } else if let v = Int(part) {
                out.append(v)
            } else {
                return nil
            }
        }
        return out.isEmpty ? nil : out
    }

    static func step(_ field: String) -> Int? {
        guard field.hasPrefix("*/"), let n = Int(field.dropFirst(2)), n > 0 else { return nil }
        return n
    }

    static func describe(minute: String, hour: String, dom: String, month: String, dow: String) -> ScheduleInfo? {
        guard month == "*" else { return nil }
        let everyDay = dom == "*" && dow == "*"
        if minute == "*", hour == "*", everyDay { return .init(text: "每分钟", period: 60, oneShot: false) }
        if let n = step(minute), hour == "*", everyDay {
            return .init(text: n == 1 ? "每分钟" : "每 \(n) 分钟", period: Double(n * 60), oneShot: false)
        }
        guard let mins = ints(minute), mins.count == 1, let m = mins.first else { return nil }
        let mm = String(format: "%02d", m)
        if hour == "*", everyDay { return .init(text: "每小时 :\(mm)", period: 3600, oneShot: false) }
        if let n = step(hour), everyDay {
            return .init(text: n == 1 ? "每小时 :\(mm)" : "每 \(n) 小时 :\(mm)", period: Double(n * 3600), oneShot: false)
        }
        guard let hours = ints(hour) else { return nil }
        let times = timesText(hours: hours, minute: m)
        if everyDay {
            return .init(text: "每天 \(times)", period: 86400 / Double(hours.count), oneShot: false)
        }
        if dom == "*", let days = ints(dow) {
            let norm = Array(Set(days.map { $0 % 7 })).sorted()
            return .init(text: "\(weekdaysText(norm)) \(times)",
                         period: 604_800 / Double(norm.count * hours.count), oneShot: false)
        }
        if dow == "*", let ds = ints(dom) {
            return .init(text: "每月 \(ds.map(String.init).joined(separator: "、")) 日 \(times)",
                         period: 2_592_000 / Double(ds.count * hours.count), oneShot: false)
        }
        return nil
    }

    static func timesText(hours: [Int], minute: Int) -> String {
        timesText(hours: hours, minutes: [minute])
    }

    static func timesText(hours: [Int], minutes: [Int]) -> String {
        let times = hours.flatMap { h in minutes.map { (h, $0) } }
        if times.count <= 2 { return times.map { hhmm($0.0, $0.1) }.joined(separator: "、") }
        let tail = minutes == [0] ? "" : " \(minutes.map(String.init).joined(separator: "/")) 分"
        return "\(times.count) 次 · \(hours.map(String.init).joined(separator: "/")) 点\(tail)"
    }

    /// days 为 0–6（0 = 周日）
    static func weekdaysText(_ days: [Int]) -> String {
        let set = Set(days)
        if set.count == 7 { return "每天" }
        if set == [1, 2, 3, 4, 5] { return "工作日" }
        if set == [0, 6] { return "周末" }
        // 周一在前、周日在后
        let ordered = set.sorted { ($0 == 0 ? 7 : $0) < ($1 == 0 ? 7 : $1) }
        return "每周" + ordered.map { weekdayNames[$0] }.joined(separator: "、")
    }

    // MARK: - RRULE（Codex）

    static func rrule(_ raw: String) -> ScheduleInfo {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.uppercased().hasPrefix("RRULE:") { s = String(s.dropFirst(6)) }
        var p: [String: String] = [:]
        for part in s.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { p[kv[0].uppercased()] = String(kv[1]) }
        }
        let interval = max(1, Int(p["INTERVAL"] ?? "") ?? 1)
        let hours = p["BYHOUR"].flatMap(ints)
        let minutes = p["BYMINUTE"].flatMap(ints) ?? [0]
        let dayMap = ["SU": 0, "MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6]
        let days = p["BYDAY"].map { list in
            list.split(separator: ",").compactMap { dayMap[String($0.suffix(2)).uppercased()] }
        }
        let timePart = hours.map { timesText(hours: $0, minutes: minutes) }
        // 每天/每周的触发次数 = 小时数 × 分钟数
        let perDay = Double((hours?.count ?? 1) * minutes.count)

        if p["COUNT"] == "1" {
            return .init(text: "一次性" + (timePart.map { " · \($0)" } ?? ""), period: nil, oneShot: true)
        }

        switch p["FREQ"]?.uppercased() {
        case "MINUTELY":
            return .init(text: interval == 1 ? "每分钟" : "每 \(interval) 分钟", period: Double(interval * 60), oneShot: false)
        case "HOURLY":
            var text = interval == 1 ? "每小时" : "每 \(interval) 小时"
            if p["BYMINUTE"] != nil { text += " " + minutes.map { ":" + String(format: "%02d", $0) }.joined(separator: "、") }
            return .init(text: text, period: Double(interval * 3600) / Double(minutes.count), oneShot: false)
        case "DAILY":
            let prefix = interval == 1 ? "每天" : "每 \(interval) 天"
            return .init(text: [prefix, timePart].compactMap { $0 }.joined(separator: " "),
                         period: 86400 * Double(interval) / perDay, oneShot: false)
        case "WEEKLY":
            if let days, !days.isEmpty {
                let dayText = Set(days).count == 7 && interval == 1
                    ? "每天"
                    : (interval == 1 ? "" : "每 \(interval) 周 ") + weekdaysText(days)
                return .init(text: [dayText, timePart].compactMap { $0 }.joined(separator: " "),
                             period: 604_800 * Double(interval) / (Double(Set(days).count) * perDay), oneShot: false)
            }
            return .init(text: [interval == 1 ? "每周" : "每 \(interval) 周", timePart].compactMap { $0 }.joined(separator: " "),
                         period: 604_800 * Double(interval), oneShot: false)
        case "MONTHLY":
            let dayText = p["BYMONTHDAY"].map { "每月 \($0) 日" } ?? "每月"
            return .init(text: [dayText, timePart].compactMap { $0 }.joined(separator: " "),
                         period: 2_592_000 * Double(interval), oneShot: false)
        default:
            return .init(text: raw, period: nil, oneShot: false)
        }
    }

    // MARK: - Claude 一次性任务

    private static let onceFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    static func once(_ date: Date) -> ScheduleInfo {
        .init(text: "一次性 · \(onceFormatter.string(from: date))", period: nil, oneShot: true)
    }

    // MARK: - launchd

    static func launchdInterval(_ seconds: Int) -> ScheduleInfo {
        let text: String
        if seconds % 3600 == 0 {
            let h = seconds / 3600
            text = h == 1 ? "每小时" : "每 \(h) 小时"
        } else if seconds % 60 == 0 {
            let m = seconds / 60
            text = m == 1 ? "每分钟" : "每 \(m) 分钟"
        } else {
            text = "每 \(seconds) 秒"
        }
        return .init(text: text, period: Double(seconds), oneShot: false)
    }

    /// StartCalendarInterval 的单个字典：缺省的键表示「任意」，与 cron 的 * 同义
    static func launchd(calendar dict: [String: Any]) -> ScheduleInfo {
        func field(_ key: String) -> String { (dict[key] as? Int).map(String.init) ?? "*" }
        let raw = "\(field("Minute")) \(field("Hour")) \(field("Day")) \(field("Month")) \(field("Weekday"))"
        let parts = raw.split(separator: " ").map(String.init)
        return describe(minute: parts[0], hour: parts[1], dom: parts[2], month: parts[3], dow: parts[4])
            ?? .init(text: "日历 \(raw)", period: nil, oneShot: false)
    }

    static func launchd(calendars: [[String: Any]]) -> ScheduleInfo {
        let infos = calendars.map { launchd(calendar: $0) }
        guard infos.count > 1 else { return infos.first ?? .init(text: "日历", period: nil, oneShot: false) }
        let text = infos.count <= 2
            ? infos.map(\.text).joined(separator: "；")
            : "\(infos.count) 个时间点 · \(infos[0].text) 等"
        // 各时间点周期相同（如每天 08:00 与 20:00）时合并为更短的间隔，否则取最频繁的那个
        let periods = infos.compactMap(\.period)
        let period: Double?
        if periods.count == infos.count, Set(periods).count == 1 {
            period = periods[0] / Double(periods.count)
        } else {
            period = periods.min()
        }
        return .init(text: text, period: period, oneShot: false)
    }
}
