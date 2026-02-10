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

    // Gradient background (deep indigo to purple)
    context.saveGState()
    context.addPath(path)
    context.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.30, green: 0.22, blue: 0.72, alpha: 1.0),  // indigo
        CGColor(red: 0.55, green: 0.25, blue: 0.85, alpha: 1.0),  // purple
    ]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    context.restoreGState()

    // Subtle inner glow
    context.saveGState()
    context.addPath(path)
    context.clip()
    let glowColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.08)
    context.setFillColor(glowColor)
    let glowRect = CGRect(x: size * 0.1, y: size * 0.4, width: size * 0.8, height: size * 0.55)
    let glowPath = CGPath(ellipseIn: glowRect, transform: nil)
    context.addPath(glowPath)
    context.fillPath()
    context.restoreGState()

    // Draw a bold forward slash "/" in the center
    let cx = size / 2
    let cy = size / 2
    let slashPath = NSBezierPath()
    let slashHeight = size * 0.38
    let slashSlant = size * 0.10
    slashPath.lineWidth = size * 0.065
    slashPath.lineCapStyle = .round
    slashPath.move(to: NSPoint(x: cx - slashSlant, y: cy - slashHeight / 2))
    slashPath.line(to: NSPoint(x: cx + slashSlant, y: cy + slashHeight / 2))
    NSColor.white.withAlphaComponent(0.95).setStroke()
    slashPath.stroke()

    // Draw a 4-point sparkle at top right
    let sx = cx + size * 0.22
    let sy = cy + size * 0.22
    let sparkleLen = size * 0.09

    let sparklePath = NSBezierPath()
    sparklePath.lineWidth = size * 0.025
    sparklePath.lineCapStyle = .round
    // Vertical arm
    sparklePath.move(to: NSPoint(x: sx, y: sy - sparkleLen))
    sparklePath.line(to: NSPoint(x: sx, y: sy + sparkleLen))
    // Horizontal arm
    sparklePath.move(to: NSPoint(x: sx - sparkleLen, y: sy))
    sparklePath.line(to: NSPoint(x: sx + sparkleLen, y: sy))
    NSColor.white.withAlphaComponent(0.85).setStroke()
    sparklePath.stroke()

    // Small sparkle dot
    let dotR = size * 0.012
    let sparkDot = NSRect(x: sx - dotR, y: sy - dotR, width: dotR * 2, height: dotR * 2)
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(ovalIn: sparkDot).fill()

    // Smaller secondary sparkle at bottom-left of slash
    let sx2 = cx - size * 0.18
    let sy2 = cy - size * 0.16
    let sparkleLen2 = size * 0.05

    let sparklePath2 = NSBezierPath()
    sparklePath2.lineWidth = size * 0.018
    sparklePath2.lineCapStyle = .round
    sparklePath2.move(to: NSPoint(x: sx2, y: sy2 - sparkleLen2))
    sparklePath2.line(to: NSPoint(x: sx2, y: sy2 + sparkleLen2))
    sparklePath2.move(to: NSPoint(x: sx2 - sparkleLen2, y: sy2))
    sparklePath2.line(to: NSPoint(x: sx2 + sparkleLen2, y: sy2))
    NSColor.white.withAlphaComponent(0.6).setStroke()
    sparklePath2.stroke()

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
