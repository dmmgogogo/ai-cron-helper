import SwiftUI

enum Palette {
    /// 近黑、略偏暖的底色
    static let canvas = Color(red: 0.047, green: 0.043, blue: 0.040)
    static let text = Color(red: 0.957, green: 0.937, blue: 0.902)
    static let sub = text.opacity(0.62)
    static let dim = text.opacity(0.38)
    static let hairline = Color.white.opacity(0.07)
    static let warn = Color(red: 1.0, green: 0.45, blue: 0.40)
}

extension JobSource {
    var tint: Color {
        switch self {
        case .claudeCode: return Color(red: 0.878, green: 0.478, blue: 0.373)   // 珊瑚橙
        case .claudeCowork: return Color(red: 0.941, green: 0.706, blue: 0.604) // 浅珊瑚
        case .codex: return Color(red: 0.298, green: 0.788, blue: 0.627)        // 薄荷绿
        case .cursor: return Color(red: 0.549, green: 0.565, blue: 0.600)
        case .launchd: return Color(red: 0.914, green: 0.725, blue: 0.286)      // 琥珀
        case .cron: return Color(red: 0.616, green: 0.690, blue: 0.784)         // 钢灰蓝
        }
    }

    var symbol: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .claudeCowork: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow"
        case .launchd: return "gearshape.2"
        case .cron: return "terminal"
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum RelativeTime {
    static func string(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let s = now.timeIntervalSince(date)
        if s < 0 { return absolute(date) }
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前" }
        if s < 86400 { return "\(Int(s / 3600)) 小时前" }
        if s < 86400 * 30 { return "\(Int(s / 86400)) 天前" }
        return absolute(date)
    }

    private static let dayFormatter = formatter("M月d日")
    private static let fullFormatter = formatter("yyyy-MM-dd HH:mm")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f
    }

    static func absolute(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func full(_ date: Date) -> String { fullFormatter.string(from: date) }
}
