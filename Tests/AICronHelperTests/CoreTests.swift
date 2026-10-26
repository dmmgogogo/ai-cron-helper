import SQLite3
import XCTest
@testable import AICronHelper

final class ScheduleTextTests: XCTestCase {
    func testCronDaily() {
        let info = ScheduleText.cron("0 10 * * *")
        XCTAssertEqual(info.text, "每天 10:00")
        XCTAssertEqual(info.period, 86400)
    }

    func testCronWeekly() {
        XCTAssertEqual(ScheduleText.cron("0 9 * * 1").text, "每周一 09:00")
        XCTAssertEqual(ScheduleText.cron("0 9 * * 7").text, "每周日 09:00")
    }

    func testCronSteps() {
        XCTAssertEqual(ScheduleText.cron("0 */6 * * *").text, "每 6 小时 :00")
        XCTAssertEqual(ScheduleText.cron("*/15 * * * *").text, "每 15 分钟")
        XCTAssertEqual(ScheduleText.cron("5 * * * *").text, "每小时 :05")
    }

    func testCronDayGroups() {
        XCTAssertEqual(ScheduleText.cron("30 8 * * 1-5").text, "工作日 08:30")
        XCTAssertEqual(ScheduleText.cron("0 10 * * 0,6").text, "周末 10:00")
        XCTAssertEqual(ScheduleText.cron("0 10 * * 0,3").text, "每周三、日 10:00")
        XCTAssertEqual(ScheduleText.cron("0 3 1 * *").text, "每月 1 日 03:00")
    }

    func testCronFallbackKeepsExpression() {
        XCTAssertEqual(ScheduleText.cron("0 0 1 1 *").text, "cron 0 0 1 1 *")
        XCTAssertEqual(ScheduleText.cron("@reboot").text, "开机时运行")
    }

    func testRRuleWithAndWithoutPrefix() {
        XCTAssertEqual(ScheduleText.rrule("RRULE:FREQ=DAILY;BYHOUR=22;BYMINUTE=30;BYSECOND=0").text, "每天 22:30")
        XCTAssertEqual(ScheduleText.rrule("FREQ=DAILY;BYHOUR=8;BYMINUTE=0;BYSECOND=0").text, "每天 08:00")
    }

    func testRRuleOneShot() {
        let info = ScheduleText.rrule("RRULE:FREQ=DAILY;COUNT=1;BYHOUR=21;BYMINUTE=35;BYSECOND=0")
        XCTAssertTrue(info.oneShot)
        XCTAssertEqual(info.text, "一次性 · 21:35")
        XCTAssertNil(info.period)
    }

    func testRRuleWeekly() {
        XCTAssertEqual(ScheduleText.rrule("FREQ=WEEKLY;BYDAY=MO;BYHOUR=10;BYMINUTE=0").text, "每周一 10:00")
        XCTAssertEqual(ScheduleText.rrule("FREQ=WEEKLY;BYDAY=SU;BYHOUR=4;BYMINUTE=10").text, "每周日 04:10")
        XCTAssertEqual(
            ScheduleText.rrule("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU;BYHOUR=23;BYMINUTE=0").text,
            "每天 23:00"
        )
    }

    func testRRuleHourlyAndMinutely() {
        XCTAssertEqual(ScheduleText.rrule("FREQ=HOURLY;INTERVAL=6").text, "每 6 小时")
        XCTAssertEqual(ScheduleText.rrule("FREQ=HOURLY;BYMINUTE=0;BYSECOND=0").text, "每小时 :00")
        XCTAssertEqual(ScheduleText.rrule("FREQ=MINUTELY;INTERVAL=15").text, "每 15 分钟")
        XCTAssertEqual(ScheduleText.rrule("FREQ=HOURLY;INTERVAL=6").period, 21600)
    }

    func testRRuleManyHoursPerDay() {
        let info = ScheduleText.rrule("FREQ=DAILY;BYHOUR=0,4,8,10,14,18;BYMINUTE=10;BYSECOND=0")
        XCTAssertEqual(info.text, "每天 6 次 · 0/4/8/10/14/18 点 10 分")
        XCTAssertEqual(info.period, 14400)
    }

    func testRRuleMultipleMinutes() {
        let hourly = ScheduleText.rrule("FREQ=HOURLY;BYMINUTE=0,30")
        XCTAssertEqual(hourly.text, "每小时 :00、:30")
        XCTAssertEqual(hourly.period, 1800)
        let daily = ScheduleText.rrule("FREQ=DAILY;BYHOUR=9;BYMINUTE=0,30")
        XCTAssertEqual(daily.text, "每天 09:00、09:30")
        XCTAssertEqual(daily.period, 43200)
    }

    func testLaunchdMultipleCalendars() {
        let same = ScheduleText.launchd(calendars: [["Hour": 8, "Minute": 0], ["Hour": 20, "Minute": 0]])
        XCTAssertEqual(same.text, "每天 08:00；每天 20:00")
        XCTAssertEqual(same.period, 43200)
        let mixed = ScheduleText.launchd(calendars: [["Weekday": 1, "Hour": 8, "Minute": 0], ["Hour": 20, "Minute": 0]])
        XCTAssertEqual(mixed.period, 86400)
    }

    func testLaunchd() {
        XCTAssertEqual(ScheduleText.launchdInterval(14400).text, "每 4 小时")
        XCTAssertEqual(ScheduleText.launchdInterval(900).text, "每 15 分钟")
        XCTAssertEqual(ScheduleText.launchdInterval(3600).text, "每小时")
        XCTAssertEqual(ScheduleText.launchd(calendar: ["Weekday": 1, "Hour": 10, "Minute": 0]).text, "每周一 10:00")
        XCTAssertEqual(ScheduleText.launchd(calendar: ["Weekday": 0, "Hour": 4, "Minute": 0]).text, "每周日 04:00")
        XCTAssertEqual(ScheduleText.launchd(calendar: ["Hour": 23, "Minute": 30]).text, "每天 23:30")
    }
}

final class TOMLLiteTests: XCTestCase {
    func testParsesFieldsAndSkipsPrompt() {
        let toml = """
        version = 1
        id = "demo"
        name = "示例 \\"任务\\""
        prompt = "示例提示词\\n第二行"
        status = "ACTIVE"
        target = { type = "project", project_id = "p" }
        cwds = ["/tmp/a", '/tmp/b']
        created_at = 1784193403707
        """
        let kv = TOMLLite.parseTopLevel(toml, skipKeys: ["prompt"])
        XCTAssertEqual(kv["id"]?.string, "demo")
        XCTAssertEqual(kv["name"]?.string, "示例 \"任务\"")
        XCTAssertNil(kv["prompt"])
        XCTAssertEqual(kv["status"]?.string, "ACTIVE")
        XCTAssertEqual(kv["cwds"]?.strings, ["/tmp/a", "/tmp/b"])
        XCTAssertEqual(kv["created_at"], .int(1_784_193_403_707))
    }

    func testMultilineStringIsSkippedEntirely() {
        let toml = "id = \"x\"\nprompt = \"\"\"\n第一行\nstatus = \"FAKE\"\n\"\"\"\nstatus = \"PAUSED\"\n"
        let kv = TOMLLite.parseTopLevel(toml, skipKeys: ["prompt"])
        XCTAssertEqual(kv["status"]?.string, "PAUSED")
        XCTAssertNil(kv["prompt"])
    }

    func testStopsAtTableHeader() {
        let kv = TOMLLite.parseTopLevel("id = \"a\"\n[sub]\nid = \"b\"\n")
        XCTAssertEqual(kv["id"]?.string, "a")
    }

    func testUnicodeEscape() {
        XCTAssertEqual(TOMLLite.parseValue("\"\\u4e2d\\u6587\""), .string("中文"))
    }
}

final class CollectorParsingTests: XCTestCase {
    func testAutomationIDFromTitle() {
        XCTAssertEqual(
            CodexRunIndex.automationID(fromTitle: "Automation: 示例\nAutomation ID: automation-3\nAutomation memory: x"),
            "automation-3"
        )
        XCTAssertNil(CodexRunIndex.automationID(fromTitle: "普通对话"))
    }

    func testCrontabParsing() {
        let text = """
        SHELL=/bin/bash
        # 注释行
        0 */6 * * * cd /tmp/demo-app && /opt/bin/bench backup >> /tmp/does-not-exist.log 2>&1 # 每 6 小时备份
        @daily /usr/local/bin/cleanup.sh
        """
        let jobs = CronCollector.parse(text)
        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs[0].name, "每 6 小时备份")
        XCTAssertEqual(jobs[0].schedule, "每 6 小时 :00")
        XCTAssertEqual(jobs[0].detail, "demo-app")
        XCTAssertEqual(jobs[1].name, "cleanup.sh")
        XCTAssertEqual(jobs[1].schedule, "每天 00:00")
    }

    func testCrontabHashInsideQuotesIsNotComment() {
        let jobs = CronCollector.parse("0 3 * * * /bin/echo \"a # b\" >>\t/tmp/x.log")
        XCTAssertEqual(jobs.first?.name, "echo")
    }

    func testLaunchdProgramNameHidesArguments() {
        XCTAssertEqual(LaunchdCollector.programName(["ProgramArguments": ["/bin/bash", "/a/b/run.sh", "--token", "x"]], fallback: "l"), "run.sh")
        XCTAssertEqual(LaunchdCollector.programName(["ProgramArguments": ["/bin/zsh", "-c", "echo secret | foo"]], fallback: "l"), "内联脚本")
        XCTAssertEqual(LaunchdCollector.programName(["ProgramArguments": ["/usr/bin/python3", "/x/job.py"]], fallback: "l"), "job.py")
    }

    func testLaunchdProgramPathWithSpace() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("含 空格 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("weekly job.sh")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        XCTAssertEqual(LaunchdCollector.programName(["ProgramArguments": [script.path]], fallback: "l"), "weekly job.sh")
        XCTAssertEqual(LaunchdCollector.programName(["ProgramArguments": ["/usr/bin/python3", script.path, "x y"]], fallback: "l"), "weekly job.sh")
    }

    func testClaudeTaskParsing() throws {
        let json = """
        {"scheduledTasks":[
          {"id":"daily","displayName":"每日检查","cronExpression":"0 10 * * *","enabled":true,"lastRunAt":"2026-10-25T02:09:37.297Z","cwd":"/tmp/proj-a"},
          {"id":"once","fireAt":1792765800000,"enabled":false,"lastRunAt":"2026-10-23T14:30:32.644Z"},
          {"id":"off","cronExpression":"0 9 * * 1","enabled":false}
        ]}
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("scheduled-tasks.json")
        try Data(json.utf8).write(to: file)

        let jobs = try ClaudeCollector.parse(file, source: .claudeCode)
        XCTAssertEqual(jobs.map(\.status), [.active, .finished, .paused])
        XCTAssertEqual(jobs[0].name, "每日检查")
        XCTAssertEqual(jobs[0].detail, "proj-a")
        XCTAssertEqual(jobs[1].name, "once")
        XCTAssertTrue(jobs[1].schedule.hasPrefix("一次性 · "))
        XCTAssertNotNil(jobs[0].lastActivity)
    }
}

final class CodexRunIndexTests: XCTestCase {
    /// 复现 Codex 关掉所有连接后的状态：WAL 模式的库，旁边没有 -wal / -shm 文件
    func testReadsWALDatabaseWithoutSidecarFiles() throws {
        // 路径带空格和中文，顺带验证 immutable 打开用的 URI 编码
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("码 库 \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("state_5.sqlite").path

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        let sql = """
        PRAGMA journal_mode=WAL;
        CREATE TABLE threads(id TEXT, title TEXT, created_at_ms INTEGER, updated_at_ms INTEGER, thread_source TEXT);
        INSERT INTO threads VALUES('t1', 'Automation: 示例' || char(10) || 'Automation ID: demo', 1792854261825, 1792854261825, 'automation');
        INSERT INTO threads VALUES('hb', '普通线程', 1, 1792900000000, 'user');
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        // 关库时 WAL 已写回主库；系统 SQLite 默认保留 -wal/-shm，手动删掉以模拟 Codex 关库后的状态
        try? FileManager.default.removeItem(atPath: path + "-wal")
        try? FileManager.default.removeItem(atPath: path + "-shm")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + "-shm"))

        let index = CodexRunIndex.load(codexHome: dir, threadIDs: ["hb"])
        XCTAssertNil(index.error)
        XCTAssertEqual(index.lastRun["demo"], Date(timeIntervalSince1970: 1_792_854_261.825))
        XCTAssertEqual(index.threadActivity["hb"], Date(timeIntervalSince1970: 1_792_900_000))
        // 只读：不能在 Codex 的目录里留下 -wal / -shm
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + "-wal"))
    }

    /// Codex 正开着库、最新记录还在 -wal 里没写回主库：必须走正常只读路径读到它
    func testReadsRowsStillInWAL() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("state_5.sqlite").path

        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &writer), SQLITE_OK)
        defer { sqlite3_close(writer) }
        let sql = """
        PRAGMA journal_mode=WAL;
        PRAGMA wal_autocheckpoint=0;
        CREATE TABLE threads(id TEXT, title TEXT, created_at_ms INTEGER, updated_at_ms INTEGER, thread_source TEXT);
        INSERT INTO threads VALUES('t1', 'Automation: 示例' || char(10) || 'Automation ID: live', 1792854261825, 1792854261825, 'automation');
        """
        XCTAssertEqual(sqlite3_exec(writer, sql, nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + "-wal"))

        let index = CodexRunIndex.load(codexHome: dir, threadIDs: [])
        XCTAssertNil(index.error)
        XCTAssertEqual(index.lastRun["live"], Date(timeIntervalSince1970: 1_792_854_261.825))
    }
}
