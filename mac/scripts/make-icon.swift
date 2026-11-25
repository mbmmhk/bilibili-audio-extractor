// 生成 App 图标：珊瑚粉圆角方块 + 白色声波竖条（中间一根带音符头）。
// 用法：swift mac/scripts/make-icon.swift
// 输出到 mac/Songline/Assets.xcassets/AppIcon.appiconset/，改了设计重新跑一遍即可。
import AppKit

let here = URL(filePath: #filePath).deletingLastPathComponent()
let out = here.appending(path: "../Songline/Assets.xcassets/AppIcon.appiconset").standardized

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS 图标的标准留白：图形占 824/1024，四周透明。
    let inset = s * 100 / 1024
    let box = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    NSGradient(colors: [
        NSColor(red: 0.98, green: 0.47, blue: 0.52, alpha: 1),
        NSColor(red: 0.86, green: 0.24, blue: 0.42, alpha: 1),
    ])!.draw(in: shape, angle: -90)

    // 声波：7 根竖条，中间高两边低。
    NSColor.white.setFill()
    let heights: [CGFloat] = [0.22, 0.38, 0.56, 0.72, 0.50, 0.34, 0.20]
    let barWidth = box.width * 0.07
    let gap = box.width * 0.045
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = box.midX - total / 2
    for h in heights {
        let height = box.height * h
        let bar = CGRect(x: x, y: box.midY - height / 2, width: barWidth, height: height)
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += barWidth + gap
    }
    // 最高那根竖条当符干，底部左侧加一个斜着的椭圆符头，看起来是一个音符：表示「歌」。
    let tallest = heights.firstIndex(of: heights.max()!)!
    let stemX = box.midX - total / 2 + CGFloat(tallest) * (barWidth + gap)
    let bottomY = box.midY - box.height * heights[tallest] / 2
    let head = NSBezierPath(ovalIn: CGRect(x: -barWidth * 1.45, y: -barWidth * 1.0,
                                           width: barWidth * 2.9, height: barWidth * 2.0))
    var turn = AffineTransform(rotationByDegrees: 22)
    turn.append(AffineTransform(translationByX: stemX - barWidth * 0.35, byY: bottomY + barWidth * 0.55))
    head.transform(using: turn)
    head.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for point in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(point)x\(point)\(scale == 2 ? "@2x" : "").png"
        try! render(point * scale).write(to: out.appending(path: name))
        images.append(["idiom": "mac", "size": "\(point)x\(point)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: out.appending(path: "Contents.json"))
print("wrote \(images.count) icons to \(out.path)")
