// Draws the app icon (1024 px) and writes Resources/AppIcon.icns via iconutil.
import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let bg = NSBezierPath(roundedRect: rect.insetBy(dx: 90, dy: 90), xRadius: 180, yRadius: 180)
    NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.55, blue: 0.15, alpha: 1), NSColor(srgbRed: 0.75, green: 0.1, blue: 0.2, alpha: 1)])?.draw(in: bg, angle: -60)
    // Horizon
    NSColor(white: 1, alpha: 0.18).setFill()
    NSBezierPath(rect: NSRect(x: 90, y: 300, width: size - 180, height: 6)).fill()
    // Jet silhouette (pointing up-right)
    let t = NSAffineTransform()
    t.translateX(by: size / 2, yBy: size / 2)
    t.rotate(byDegrees: -40)
    t.concat()
    let jet = NSBezierPath()
    jet.move(to: NSPoint(x: 0, y: 330))
    jet.line(to: NSPoint(x: 45, y: 150)); jet.line(to: NSPoint(x: 280, y: -40)); jet.line(to: NSPoint(x: 280, y: -95))
    jet.line(to: NSPoint(x: 50, y: -60)); jet.line(to: NSPoint(x: 40, y: -200)); jet.line(to: NSPoint(x: 130, y: -280))
    jet.line(to: NSPoint(x: 130, y: -320)); jet.line(to: NSPoint(x: 0, y: -280)); jet.line(to: NSPoint(x: -130, y: -320))
    jet.line(to: NSPoint(x: -130, y: -280)); jet.line(to: NSPoint(x: -40, y: -200)); jet.line(to: NSPoint(x: -50, y: -60))
    jet.line(to: NSPoint(x: -280, y: -95)); jet.line(to: NSPoint(x: -280, y: -40)); jet.line(to: NSPoint(x: -45, y: 150))
    jet.close()
    NSColor.white.setFill()
    jet.fill()
    return true
}
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
