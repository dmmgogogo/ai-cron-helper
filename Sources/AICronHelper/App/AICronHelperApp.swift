import SwiftUI

struct AICronHelperApp: App {
    @StateObject private var store = JobStore()
    @StateObject private var updater = UpdateController()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(store)
                .environmentObject(updater)
        } label: {
            Image(nsImage: MenuBarIcon.image(count: store.activeCount, badge: updater.availableVersion != nil))
                .accessibilityLabel("AI 定时任务，运行中 \(store.activeCount) 个\(updater.availableVersion == nil ? "" : "，有新版本")")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class JobStore: ObservableObject {
    @Published private(set) var reports: [SourceReport] = []
    @Published private(set) var jobs: [ScheduledJob] = []
    @Published private(set) var activeCount = 0
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { [weak self] in
            // 读文件和跑 launchctl 放到后台线程，结果回主线程更新
            let result = await Task.detached(priority: .utility) { Collector.collectAll() }.value
            guard let self else { return }
            self.reports = result
            self.jobs = result.flatMap(\.jobs)
            self.activeCount = self.jobs.filter { $0.status == .active }.count
            self.lastRefresh = Date()
            self.isRefreshing = false
        }
    }
}

/// 菜单栏图标：轨道 + 运行中数量，整体画成一张 template 图，深浅色菜单栏都自动适配。
/// badge 为 true 时在右上角加一个小圆点，提示有新版本
enum MenuBarIcon {
    static func image(count: Int, badge: Bool = false) -> NSImage {
        let text = "\(count)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let textSize = text.size(withAttributes: attrs)
        let glyph: CGFloat = 16
        let gap: CGFloat = 4
        let badgeWidth: CGFloat = badge ? 5 : 0
        let size = NSSize(width: ceil(glyph + gap + textSize.width + badgeWidth), height: 18)

        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.set()
            let c = NSPoint(x: glyph / 2, y: size.height / 2)
            let r: CGFloat = 6.3
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ring.lineWidth = 1.5
            ring.stroke()
            NSBezierPath(ovalIn: NSRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)).fill()

            // 右上角的卫星：先在轨道上挖出空隙再画点，小尺寸下更清楚
            let p = NSPoint(x: c.x + r * cos(.pi / 4), y: c.y + r * sin(.pi / 4))
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: p.x - 3.3, y: p.y - 3.3, width: 6.6, height: 6.6)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: NSRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4)).fill()

            text.draw(at: NSPoint(x: glyph + gap, y: (size.height - textSize.height) / 2), withAttributes: attrs)
            if badge {
                NSBezierPath(ovalIn: NSRect(x: size.width - 4.6, y: size.height - 6.6, width: 4.6, height: 4.6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
