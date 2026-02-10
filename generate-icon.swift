#!/usr/bin/env swift

import AppKit

func generateIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let context = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22

    // Rounded rect path
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Soft indigo-to-blue gradient background
    context.saveGState()
    context.addPath(path)
    context.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.25, green: 0.22, blue: 0.55, alpha: 1.0),  // soft indigo
        CGColor(red: 0.30, green: 0.45, blue: 0.72, alpha: 1.0),  // muted blue
    ]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])
    context.restoreGState()

    // Matte white slash
    let cx = size / 2
    let cy = size / 2
    let slashPath = NSBezierPath()
    slashPath.lineWidth = size * 0.06
    slashPath.lineCapStyle = .round
    slashPath.move(to: NSPoint(x: cx - size * 0.11, y: cy - size * 0.21))
    slashPath.line(to: NSPoint(x: cx + size * 0.11, y: cy + size * 0.21))
    NSColor.white.withAlphaComponent(0.95).setStroke()
    slashPath.stroke()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String, pixelSize: Int) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("Generated: \(path) (\(pixelSize)x\(pixelSize))")
}

// Generate all sizes needed for macOS app icon
let basePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

let icon = generateIcon(size: 1024)

for spec in sizes {
    let pixelSize = spec.points * spec.scale
    let suffix = spec.scale > 1 ? "@\(spec.scale)x" : ""
    let filename = "icon_\(spec.points)x\(spec.points)\(suffix).png"
    let path = "\(basePath)/\(filename)"
    savePNG(icon, to: path, pixelSize: pixelSize)
}

print("Done! Generated \(sizes.count) icon files.")
