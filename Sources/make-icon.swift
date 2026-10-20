import AppKit

// Vector artwork rasterized at every native macOS icon size.
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(calibratedRed: 0.11, green: 0.06, blue: 0.25, alpha: 1), ending: NSColor(calibratedRed: 0.53, green: 0.20, blue: 0.89, alpha: 1))!.draw(in: tile, angle: 60)
    let ring = NSBezierPath(ovalIn: NSRect(x: 204, y: 204, width: 616, height: 616))
    ring.lineWidth = 30
    NSColor.white.withAlphaComponent(0.30).setStroke()
    ring.stroke()
    // Audio waveform with a central stop control.
    NSColor.white.setFill()
    for (x, height) in [(290, 130), (370, 260), (610, 260), (690, 130)] {
        NSBezierPath(roundedRect: NSRect(x: x, y: 512 - height / 2, width: 44, height: height), xRadius: 22, yRadius: 22).fill()
    }
    NSBezierPath(roundedRect: NSRect(x: 446, y: 436, width: 132, height: 152), xRadius: 24, yRadius: 24).fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16"]
    case 32: names = ["icon_16x16@2x", "icon_32x32"]
    case 64: names = ["icon_32x32@2x"]
    case 128: names = ["icon_128x128"]
    case 256: names = ["icon_128x128@2x", "icon_256x256"]
    case 512: names = ["icon_256x256@2x", "icon_512x512"]
    default: names = ["icon_512x512@2x"]
    }
    for name in names { try data.write(to: URL(fileURLWithPath: folder + "/" + name + ".png")) }
}
