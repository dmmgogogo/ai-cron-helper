import Foundation

/// 定时任务的来源
enum JobSource: String, CaseIterable, Codable, Identifiable {
    case claudeCode, claudeCowork, codex, cursor, launchd, cron

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .claudeCowork: return "Claude Cowork"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .launchd: return "launchd"
        case .cron: return "crontab"
        }
    }

    /// launchd / crontab 归入「系统级」，其余是 AI 应用
    var isSystem: Bool { self == .launchd || self == .cron }
}

enum JobStatus: String, Codable {
    case active    // 运行中（会按计划继续触发）
    case paused    // 已暂停 / 未加载
    case finished  // 一次性任务，已经跑过
}

/// 统一后的定时任务。只保存名称、调度和状态，不保存任务的 prompt 正文
struct ScheduledJob: Identifiable, Codable, Hashable {
    let id: String
    let source: JobSource
    let name: String
    /// 人类可读的调度，如「每天 10:00」
    let schedule: String
    /// 原始调度表达式（cron / RRULE / launchd 字段），用于悬停提示
    let rawSchedule: String
    let status: JobStatus
    let lastActivity: Date?
    /// lastActivity 的口径：「上次运行」「线程活动」「日志更新」
    let lastActivityLabel: String
    /// 项目目录名或程序名
    let detail: String?
    let tag: String?
    /// 需要注意的问题，如「上次退出码 3」
    let issue: String?
    /// 点击时在 Finder 中定位的配置文件
    let filePath: String?
    /// 大致触发间隔（秒），随 --dump 输出供核对
    let periodSeconds: Double?
}

struct SourceReport: Codable, Identifiable {
    var id: String { source.rawValue }
    let source: JobSource
    /// 本机是否装了这个来源（没装时界面显示「未检测到」）
    let available: Bool
    let note: String?
    let jobs: [ScheduledJob]
}

extension String {
    /// 跨进程稳定的哈希（Swift 自带 hashValue 每次启动都会变）
    var stableHash: UInt64 {
        var h: UInt64 = 5381
        for b in utf8 { h = (h &* 33) &+ UInt64(b) }
        return h
    }
}
