import Combine
import Sparkle
import SwiftUI

/// 自动更新（Sparkle）。
/// 后台定时检查到新版本时不抢焦点弹窗：菜单栏图标加红点、面板顶部出现提示，
/// 用户点开后再由 Sparkle 显示更新说明、下载、校验签名、安装并重启。
@MainActor
final class UpdateController: NSObject, ObservableObject {
    /// 后台检查到、但用户还没看过的新版本号
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheckForUpdates = false
    private var controller: SPUStandardUpdaterController?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

    override init() {
        super.init()
        // 直接运行 .build 里的裸可执行文件（开发调试）时没有更新配置，不启动 Sparkle
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        self.controller = controller
    }

    func checkForUpdates() {
        guard let controller else { return }
        bringToFront()
        controller.checkForUpdates(nil)
        // 没开启会话（例如正在后台检查）时收不到会话结束回调，要自己切回菜单栏模式，否则会一直留着 Dock 图标
        if !controller.updater.sessionInProgress { NSApp.setActivationPolicy(.accessory) }
    }

    /// 菜单栏 App 是 accessory 模式，面板也不抢焦点，直接 activate 会被系统拒绝，更新窗口就压在别的窗口后面。
    /// 按 Sparkle 文档对后台 App 的做法，更新期间临时切成 regular（可激活、出现在 Dock 和 ⌘Tab），会话结束再切回去。
    private func bringToFront() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate {
            bringToFront()
        } else {
            availableVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
