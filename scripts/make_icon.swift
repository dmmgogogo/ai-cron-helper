// 生成 App 图标的 iconset：swift scripts/make_icon.swift <输出目录.iconset>
// 用 CoreGraphics 画在 1024 画布上，再按各尺寸缩放输出，避免手工估尺寸
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// 与面板 JobSource.tint 一致
let coral: UInt32 = 0xE07A5F
let mint: UInt32 = 0x4CC9A0
let amber: UInt32 = 0xE9B949
let steel: UInt32 = 0x9DB0C8
let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// 从 12 点方向顺时针画一段圆弧，fraction 为整圈比例
func arc(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat, from: CGFloat, to: CGFloat) {
    let start = (90 - from * 360) * .pi / 180
    let end = (90 - to * 360) * .pi / 180
    ctx.beginPath()
    ctx.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: true)
    ctx.strokePath()
}

func draw(_ ctx: CGContext) {
    // macOS 图标网格：1024 画布里主体 824，圆角约 185
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.30))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0x0E0D0C))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // 底色：自上而下很轻的明暗过渡，和面板顶部的淡提亮一致
    let base = CGGradient(colorsSpace: space, colors: [rgb(0x22201D), rgb(0x0E0D0C)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // 分段环：深灰轨道 = 已停，彩色段 = 各来源运行中
    let c = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 248
    let lineWidth: CGFloat = 60
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.08))
    ctx.strokeEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))

    let segments: [(color: UInt32, span: CGFloat)] = [(coral, 0.10), (mint, 0.30), (amber, 0.26), (steel, 0.07)]
    // 圆头会向两侧各多出半个线宽，扣掉它再留一点间隙
    let inset = (lineWidth / 2) / (2 * .pi * radius) + 0.012
    var cursor: CGFloat = 0
    for seg in segments {
        ctx.setStrokeColor(rgb(seg.color))
        arc(ctx, center: c, radius: radius, from: cursor + inset, to: max(cursor + inset, cursor + seg.span - inset))
        cursor += seg.span
    }

    // 中心点
    ctx.setFillColor(rgb(0xF4EFE6))
    ctx.fillEllipse(in: CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 68))

    // 内描边高光
    ctx.addPath(shape)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.07))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()
}

func render(size: Int, to url: URL) throws {
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "icon", code: 1)
    }
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(ctx)
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 2)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 3) }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("用法：swift scripts/make_icon.swift <输出目录.iconset>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in specs {
    try render(size: px, to: out.appendingPathComponent(name))
}
print("已生成 \(specs.count) 个尺寸 → \(out.path)")
