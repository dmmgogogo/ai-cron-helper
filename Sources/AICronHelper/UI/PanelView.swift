import SwiftUI
import ServiceManagement

enum StatusFilter: String, CaseIterable, Identifiable {
    case active, stopped, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "运行中"
        case .stopped: return "已停"
        case .all: return "全部"
        }
    }

    func matches(_ job: ScheduledJob) -> Bool {
        switch self {
        case .active: return job.status == .active
        case .stopped: return job.status != .active
        case .all: return true
        }
    }
}

struct PanelView: View {
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var updater: UpdateController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: StatusFilter = .active
    @State private var sourceFilter: JobSource?
    @State private var visible = false
    @Namespace private var pillSpace

    private var animate: Bool { visible && !reduceMotion }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.canvas
            // 顶部一层很淡的暖色提亮，区分头部和列表，不做动态背景
            LinearGradient(colors: [Color.white.opacity(0.045), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
            VStack(spacing: 0) {
                header
                if let version = updater.availableVersion { updateBanner(version) }
                hero
                filterBar
                Rectangle().fill(Palette.hairline).frame(height: 1)
                jobList
                footer
            }
        }
        .frame(width: 392, height: 640)
        .environment(\.colorScheme, .dark)
        .onAppear {
            visible = true
            store.refresh()
        }
        .onDisappear { visible = false }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AI 定时任务")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text("本机 \(store.jobs.count) 个任务 · \(store.reports.filter { !$0.jobs.isEmpty }.count) 个来源")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.dim)
            }
            Spacer()
            RefreshButton(spinning: store.isRefreshing) { store.refresh() }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                SourceRing(segments: ringSegments, total: store.jobs.count, animate: animate)
                VStack(spacing: 2) {
                    Text("\(store.activeCount)")
                        .font(.system(size: 40, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.4), value: store.activeCount)
                    Text("运行中")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.dim)
                }
            }
            .frame(width: 148, height: 148)
            SourceBreakdown(reports: store.reports, selected: $sourceFilter)
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: 筛选

    private var scopedJobs: [ScheduledJob] {
        store.jobs.filter { sourceFilter == nil || $0.source == sourceFilter }
    }

    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(StatusFilter.allCases) { f in
                let selected = filter == f
                Button {
                    withAnimation(.smooth(duration: 0.28)) { filter = f }
                } label: {
                    HStack(spacing: 5) {
                        Text(f.title).font(.system(size: 12, weight: .medium))
                        Text("\(scopedJobs.filter(f.matches).count)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(selected ? Palette.sub : Palette.dim)
                    }
                    .foregroundStyle(selected ? Palette.text : Palette.sub)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Color.white.opacity(0.09))
                                .matchedGeometryEffect(id: "pill", in: pillSpace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            Spacer()
            if let s = sourceFilter {
                Button {
                    withAnimation(.smooth(duration: 0.25)) { sourceFilter = nil }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(s.tint).frame(width: 6, height: 6)
                        Text(s.title).font(.system(size: 11, weight: .medium))
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Palette.sub)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .help("清除来源筛选")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: 列表

    private var groups: [(source: JobSource, jobs: [ScheduledJob])] {
        let rank: [JobStatus: Int] = [.active: 0, .paused: 1, .finished: 2]
        return JobSource.allCases.compactMap { source in
            let jobs = scopedJobs
                .filter { $0.source == source && filter.matches($0) }
                .sorted {
                    if $0.status != $1.status { return rank[$0.status]! < rank[$1.status]! }
                    return ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
                }
            return jobs.isEmpty ? nil : (source, jobs)
        }
    }

    private var jobList: some View {
        let groups = self.groups
        var order: [String: Int] = [:]
        for job in groups.flatMap(\.jobs) { order[job.id] = order.count }

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if groups.isEmpty {
                    emptyState
                }
                ForEach(groups, id: \.source) { group in
                    VStack(alignment: .leading, spacing: 1) {
                        SectionHeader(source: group.source, count: group.jobs.count)
                        ForEach(group.jobs) { job in
                            JobRow(job: job, animate: animate, index: order[job.id] ?? 0)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Palette.dim)
            Text(store.lastRefresh == nil ? "正在读取…" : "这里没有\(filter == .all ? "" : filter.title)的任务")
                .font(.system(size: 12))
                .foregroundStyle(Palette.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // MARK: 底栏

    private func updateBanner(_ version: String) -> some View {
        Button { updater.checkForUpdates() } label: {
            HStack(spacing: 8) {
                Circle().fill(JobSource.claudeCode.tint).frame(width: 6, height: 6)
                Text("发现新版本 v\(version)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("查看更新")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.sub)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.dim)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("发现新版本 v\(version)，查看更新")
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("v\(updater.currentVersion) · " + (store.lastRefresh.map { "更新于 \(Self.clock.string(from: $0))" } ?? "读取中…"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.dim)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("检查更新") { updater.checkForUpdates() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(updater.canCheckForUpdates ? Palette.sub : Palette.dim)
                .disabled(!updater.canCheckForUpdates)
                .help(updater.canCheckForUpdates ? "检查 GitHub 上是否有新版本" : "正在检查更新，或有待处理的更新")
            LaunchAtLoginToggle()
            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.sub)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Color.white.opacity(0.03))
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var ringSegments: [SourceRing.Segment] {
        JobSource.allCases.map { source in
            SourceRing.Segment(
                id: source,
                color: source.tint,
                count: store.jobs.filter { $0.source == source && $0.status == .active }.count
            )
        }
    }
}

// MARK: - 来源分布

struct SourceBreakdown: View {
    let reports: [SourceReport]
    @Binding var selected: JobSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            groupLabel("AI 应用")
            ForEach(reports.filter { !$0.source.isSystem }) { row($0) }
            groupLabel("系统级").padding(.top, 6)
            ForEach(reports.filter { $0.source.isSystem }) { row($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(Palette.dim)
            .padding(.leading, 8)
            .padding(.bottom, 1)
    }

    private func row(_ report: SourceReport) -> some View {
        let active = report.jobs.filter { $0.status == .active }.count
        let isSelected = selected == report.source
        let empty = report.jobs.isEmpty
        return Button {
            withAnimation(.smooth(duration: 0.25)) { selected = isSelected ? nil : report.source }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(report.source.tint.opacity(empty ? 0.3 : 1))
                    .frame(width: 6, height: 6)
                Text(report.source.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(empty ? Palette.dim : Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if empty {
                    Text(report.available ? "无" : "未检测到")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.dim)
                } else {
                    HStack(spacing: 0) {
                        Text("\(active)").foregroundStyle(Palette.text)
                        Text("/\(report.jobs.count)").foregroundStyle(Palette.dim)
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 21)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(isSelected ? 0.09 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(empty)
        .help(report.note ?? "\(report.source.title)：运行中 \(active) / 共 \(report.jobs.count)，点击只看这一类")
    }
}

struct SectionHeader: View {
    let source: JobSource
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: source.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(source.tint)
            Text(source.title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Palette.sub)
            Text("\(count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.dim)
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - 任务行

struct JobRow: View {
    let job: ScheduledJob
    let animate: Bool
    let index: Int
    @State private var hovering = false
    @State private var appeared = false

    var body: some View {
        let live = job.status == .active
        HStack(spacing: 10) {
            StatusGlyph(status: job.status, tint: job.source.tint, animate: animate,
                        delay: Double(job.id.stableHash % 20) / 10)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(job.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(live ? Palette.text : Palette.sub)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let tag = job.tag { TagChip(text: tag) }
                    if job.status == .finished { TagChip(text: "已结束") }
                }
                HStack(spacing: 5) {
                    Text(job.schedule)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(live ? job.source.tint : Palette.dim)
                        .lineLimit(1)
                    if let detail = job.detail {
                        Text("·").foregroundStyle(Palette.dim)
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.dim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(RelativeTime.string(job.lastActivity))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.sub)
                Text(job.issue ?? job.lastActivityLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(job.issue == nil ? Palette.dim : Palette.warn)
                    .lineLimit(1)
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.055 : 0))
        )
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture(perform: reveal)
        .help(tooltip)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            guard !appeared else { return }
            if animate {
                withAnimation(.easeOut(duration: 0.35).delay(min(Double(index) * 0.025, 0.4))) { appeared = true }
            } else {
                appeared = true
            }
        }
    }

    private var tooltip: String {
        var lines = [job.name, "调度：\(job.schedule)"]
        if !job.rawSchedule.isEmpty { lines.append("原始：\(job.rawSchedule)") }
        if let d = job.lastActivity { lines.append("\(job.lastActivityLabel)：\(RelativeTime.full(d))") }
        if let issue = job.issue { lines.append("注意：\(issue)") }
        if job.filePath != nil { lines.append("点击在 Finder 中显示配置文件") }
        return lines.joined(separator: "\n")
    }

    private func reveal() {
        // 受保护位置不先检查存在性（会弹授权框），直接交给 Finder
        guard let path = job.filePath,
              ProtectedPaths.contains(path) || FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Palette.sub)
            .padding(.horizontal, 5)
            .frame(height: 15)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

// MARK: - 小控件

struct RefreshButton: View {
    let spinning: Bool
    let action: () -> Void
    @State private var angle: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.sub)
                .rotationEffect(.degrees(angle))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help("立即刷新")
        .accessibilityLabel("立即刷新")
        .onChange(of: spinning) { _, isSpinning in
            if isSpinning { withAnimation(.easeOut(duration: 0.6)) { angle += 360 } }
        }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var message: String?

    var body: some View {
        Toggle(isOn: Binding(get: { enabled }, set: apply)) {
            Text("开机启动")
                .font(.system(size: 11))
                .foregroundStyle(Palette.sub)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .help(message ?? "登录 macOS 后自动出现在菜单栏")
        // 用户可能在系统设置里改过，每次打开面板重新读取
        .onAppear { enabled = SMAppService.mainApp.status == .enabled }
    }

    private func apply(_ on: Bool) {
        // 状态已一致时什么都不做，避免重复注册/注销
        guard on != (SMAppService.mainApp.status == .enabled) else {
            enabled = on
            return
        }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            message = nil
        } catch {
            message = "设置失败：\(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        if status == .requiresApproval {
            message = "需要在「系统设置 → 通用 → 登录项」里允许"
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
