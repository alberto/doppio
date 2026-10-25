// Renders Doppio's app icon into Resources/AppIcon.icns from Resources/IconSource.png.
// Usage: swift Scripts/make-icon.swift [preview.png]
import AppKit

let canvas: CGFloat = 1024
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let source = NSImage(contentsOf: resources.appendingPathComponent("IconSource.png"))!
/// Square region of the source photo (in its own points, origin bottom-left) framed around the cup.
let crop = NSRect(x: 232, y: 80, width: 1040, height: 1040)

func drawIcon() {
    // macOS icon grid: 824 pt rounded square centered on the 1024 canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let dropShadow = NSShadow()
    dropShadow.shadowColor = NSColor(white: 0, alpha: 0.3)
    dropShadow.shadowOffset = NSSize(width: 0, height: -10)
    dropShadow.shadowBlurRadius = 24
    dropShadow.set()
    NSColor.white.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The photo has a white background, so it fills the tile seamlessly.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSColor.white.setFill()
    tile.fill()
    source.draw(in: tile, from: crop, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try! png(render(pixels: points)).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try! png(render(pixels: points * 2)).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try! FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
if CommandLine.arguments.count > 1 {
    try! png(render(pixels: 1024)).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
