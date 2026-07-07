// Renders Assets/AppIcon.png (1024) natively — the app's five-dot meter motif
// (3 filled + 2 hollow) in cream on a terracotta gradient tile. Run from repo
// root: `swift Scripts/make-icon.swift`. No dependencies.
import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Rounded-square tile clipped, filled with a warm terracotta gradient.
let rect = CGRect(x: 0, y: 0, width: size, height: size)
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 230, cornerHeight: 230, transform: nil))
ctx.clip()
let space = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: space, colors: [
    NSColor(srgbRed: 0.882, green: 0.549, blue: 0.396, alpha: 1).cgColor,  // #E18C65 top
    NSColor(srgbRed: 0.773, green: 0.325, blue: 0.161, alpha: 1).cgColor,  // #C55329 bottom
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// Five dots: 3 filled, 2 hollow — the menu-bar meter.
let cream = NSColor(srgbRed: 0.984, green: 0.953, blue: 0.914, alpha: 1).cgColor
let r = 62.0, gap = 52.0
let total = 5 * 2 * r + 4 * gap
var cx = (size - total) / 2 + r
let cy = size / 2
for i in 0..<5 {
    let dot = CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)
    if i < 3 {
        ctx.setFillColor(cream)
        ctx.fillEllipse(in: dot)
    } else {
        ctx.setStrokeColor(cream)
        ctx.setLineWidth(16)
        ctx.strokeEllipse(in: dot.insetBy(dx: 8, dy: 8))
    }
    cx += 2 * r + gap
}

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "Assets/AppIcon.png"))
print("wrote Assets/AppIcon.png (\(png.count) bytes)")
