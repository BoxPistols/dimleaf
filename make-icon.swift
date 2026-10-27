// Dimleaf.icns を作る: swift make-icon.swift && iconutil -c icns Dimleaf.iconset
// 葉は同じ半径の 2 円の共通部分（レンズ）。決める数は 半径 r・中心のずれ a・切れ目の幅 g の 3 つだけで、
// 長さ 2√(r²−a²)・幅 2(r−a) はそこから決まる。中央の切れ目で 2 枚に分け、片側を暗くして「明るさを落とす」を表す
import AppKit

let canvas: CGFloat = 1024
// macOS のアイコン格子: 824 の角丸四角を中央に置く
let plate = CGRect(x: 100, y: 100, width: 824, height: 824), corner: CGFloat = 185
let r: CGFloat = 350, a: CGFloat = 210, g: CGFloat = 26

// 使う色: 地は暗い緑、葉は明るい緑と、同じ色相で明度を落とした緑。避ける色: グラデーション・光沢・彩度の高い蛍光色
let ground = NSColor(srgbRed: 0.09, green: 0.15, blue: 0.11, alpha: 1)
let lit = NSColor(srgbRed: 0.55, green: 0.80, blue: 0.53, alpha: 1)
let dim = NSColor(srgbRed: 0.24, green: 0.43, blue: 0.29, alpha: 1)

func draw(_ ctx: CGContext) {
    ctx.addPath(CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setFillColor(ground.cgColor)
    ctx.fillPath()
    // 葉の軸を右上がり 45° にする
    ctx.translateBy(x: canvas / 2, y: canvas / 2)
    ctx.rotate(by: -.pi / 4)
    let lens = CGMutablePath()
    lens.addEllipse(in: CGRect(x: -a - r, y: -r, width: 2 * r, height: 2 * r))
    let right = CGPath(ellipseIn: CGRect(x: a - r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
    let h = (r * r - a * a).squareRoot()
    for (side, color) in [(CGFloat(-1), lit), (1, dim)] {
        ctx.saveGState()
        // 軸の片側だけを残す（切れ目の幅 g の半分ずつ空ける）
        ctx.clip(to: CGRect(x: side < 0 ? -r : g / 2, y: -h, width: r - g / 2, height: 2 * h))
        ctx.addPath(lens); ctx.clip()
        ctx.addPath(right); ctx.clip()
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: -r, y: -h, width: 2 * r, height: 2 * h))
        ctx.restoreGState()
    }
}

let dir = URL(fileURLWithPath: "Dimleaf.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        ctx.scaleBy(x: CGFloat(px) / canvas, y: CGFloat(px) / canvas)
        draw(ctx)
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
    }
}
