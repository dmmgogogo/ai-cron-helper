import SwiftUI

/// 分段环形图：整圈代表全部任务，每段是一个来源的「运行中」数量，空着的轨道就是已停的任务。
/// 打开面板时从 0 画满；之后只有一道很淡的高光缓慢绕环流过。
struct SourceRing: View {
    struct Segment: Identifiable {
        let id: JobSource
        let color: Color
        let count: Int
    }

    let segments: [Segment]
    let total: Int
    let animate: Bool
    @State private var progress: CGFloat = 0

    private let lineWidth: CGFloat = 6
    /// 相邻两段之间留出的角度
    private let gapDegrees: Double = 3

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = (side - lineWidth) / 2
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
                ZStack {
                    ForEach(arcs(radius: radius), id: \.id) { arc in
                        Circle()
                            .trim(from: arc.from, to: arc.to)
                            .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                    if animate { sheen }
                }
                .mask(
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(style: StrokeStyle(lineWidth: lineWidth + 2))
                )
            }
            .rotationEffect(.degrees(-90))
            .padding(lineWidth / 2)
            .frame(width: side, height: side)
        }
        .onAppear {
            guard animate else {
                progress = 1
                return
            }
            progress = 0
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.1)) { progress = 1 }
        }
        .onChange(of: animate) { _, on in
            if !on { progress = 1 }
        }
    }

    /// 高光：一小段渐变沿环慢慢转，8 秒一圈，限帧 24fps
    private var sheen: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animate)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = (t.truncatingRemainder(dividingBy: 8) / 8) * 360
            Circle()
                .stroke(
                    AngularGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0), location: 0.82),
                            .init(color: .white.opacity(0.45), location: 0.97),
                            .init(color: .white.opacity(0), location: 1),
                        ],
                        center: .center,
                        angle: .degrees(angle)
                    ),
                    lineWidth: lineWidth
                )
                .blendMode(.plusLighter)
        }
    }

    private func arcs(radius: CGFloat) -> [(id: JobSource, color: Color, from: CGFloat, to: CGFloat)] {
        guard total > 0 else { return [] }
        let live = segments.filter { $0.count > 0 }
        // 圆头端点会向两侧各多画半个线宽，这里换算成比例一并扣掉
        let capInset = Double(lineWidth / 2) / Double(2 * .pi * radius)
        let gap = gapDegrees / 360
        var cursor = 0.0
        var out: [(JobSource, Color, CGFloat, CGFloat)] = []
        for seg in live {
            let span = Double(seg.count) / Double(total)
            var from = cursor + capInset + gap / 2
            var to = cursor + span - capInset - gap / 2
            if to < from {
                // 段太短时退化成一个圆点
                let mid = cursor + span / 2
                from = mid
                to = mid
            }
            out.append((seg.id, seg.color, CGFloat(from), CGFloat(to)))
            cursor += span
        }
        return out
    }
}

/// 状态点：运行中的会错相呼吸
struct StatusGlyph: View {
    let status: JobStatus
    let tint: Color
    let animate: Bool
    let delay: Double

    var body: some View {
        ZStack {
            switch status {
            case .active:
                PulseRing(color: NSColor(tint), animate: animate, phase: delay)
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            case .paused:
                Circle()
                    .stroke(Palette.dim, lineWidth: 1.2)
                    .frame(width: 7, height: 7)
            case .finished:
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.dim)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// 扩散的圆环。用 Core Animation 图层动画实现：动画由系统渲染服务执行，
/// 不像 SwiftUI 的 repeatForever 那样在应用进程里按 120Hz 逐帧重绘（几十行叠加时 CPU 会到 20%）
struct PulseRing: NSViewRepresentable {
    let color: NSColor
    let animate: Bool
    /// 相位偏移（秒），让各行错开
    let phase: Double

    func makeNSView(context: Context) -> PulseRingView { PulseRingView() }

    func updateNSView(_ view: PulseRingView, context: Context) {
        view.update(color: color, animate: animate, phase: phase)
    }
}

final class PulseRingView: NSView {
    private let ring = CAShapeLayer()
    private var animate = false
    private var phase = 0.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ring.fillColor = nil
        ring.lineWidth = 1
        ring.opacity = 0
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.bounds = CGRect(x: 0, y: 0, width: 7, height: 7)
        ring.position = CGPoint(x: bounds.midX, y: bounds.midY)
        ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAnimation()
    }

    func update(color: NSColor, animate: Bool, phase: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeColor = color.withAlphaComponent(0.6).cgColor
        CATransaction.commit()
        let changed = animate != self.animate || phase != self.phase
        self.animate = animate
        self.phase = phase
        if changed { applyAnimation() }
    }

    private func applyAnimation() {
        ring.removeAnimation(forKey: "pulse")
        guard animate, window != nil else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 2.2
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 2
        group.repeatCount = .infinity
        group.timeOffset = phase
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "pulse")
    }
}
