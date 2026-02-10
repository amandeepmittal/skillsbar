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

    // Dark background (near-black charcoal)
    context.saveGState()
    context.addPath(path)
    context.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0),  // deep charcoal
        CGColor(red: 0.12, green: 0.11, blue: 0.18, alpha: 1.0),  // slightly lighter at top
    ]
    let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: [0.0, 1.0])!
    context.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])
    context.restoreGState()

    // Soft ambient glow behind the slash (cyan tinted)
    context.saveGState()
    context.addPath(path)
    context.clip()
    let ambientRect = CGRect(x: size * 0.15, y: size * 0.15, width: size * 0.7, height: size * 0.7)
    let ambientColors = [
        CGColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 0.15),  // cyan center
        CGColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 0.0),   // fade out
    ]
    let ambientGradient = CGGradient(colorsSpace: colorSpace, colors: ambientColors as CFArray, locations: [0.0, 1.0])!
    context.drawRadialGradient(
        ambientGradient,
        startCenter: CGPoint(x: size * 0.5, y: size * 0.5),
        startRadius: 0,
        endCenter: CGPoint(x: size * 0.5, y: size * 0.5),
        endRadius: size * 0.4,
        options: []
    )
    context.restoreGState()

    // Outer bloom / glow for the slash (larger, softer)
    context.saveGState()
    context.addPath(path)
    context.clip()
    let bloomColors = [
        CGColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.25),
        CGColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.0),
    ]
    let bloomGradient = CGGradient(colorsSpace: colorSpace, colors: bloomColors as CFArray, locations: [0.0, 1.0])!
    context.drawRadialGradient(
        bloomGradient,
        startCenter: CGPoint(x: size * 0.5, y: size * 0.5),
        startRadius: 0,
        endCenter: CGPoint(x: size * 0.5, y: size * 0.5),
        endRadius: size * 0.32,
        options: []
    )
    context.restoreGState()

    // Neon slash with glow layers
    let cx = size / 2
    let cy = size / 2
    let slashHeight = size * 0.42
    let slashSlant = size * 0.11

    // Layer 1: wide soft glow
    let glow1 = NSBezierPath()
    glow1.lineWidth = size * 0.14
    glow1.lineCapStyle = .round
    glow1.move(to: NSPoint(x: cx - slashSlant, y: cy - slashHeight / 2))
    glow1.line(to: NSPoint(x: cx + slashSlant, y: cy + slashHeight / 2))
    NSColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 0.12).setStroke()
    glow1.stroke()

    // Layer 2: medium glow
    let glow2 = NSBezierPath()
    glow2.lineWidth = size * 0.09
    glow2.lineCapStyle = .round
    glow2.move(to: NSPoint(x: cx - slashSlant, y: cy - slashHeight / 2))
    glow2.line(to: NSPoint(x: cx + slashSlant, y: cy + slashHeight / 2))
    NSColor(red: 0.0, green: 0.88, blue: 1.0, alpha: 0.25).setStroke()
    glow2.stroke()

    // Layer 3: bright core
    let core = NSBezierPath()
    core.lineWidth = size * 0.05
    core.lineCapStyle = .round
    core.move(to: NSPoint(x: cx - slashSlant, y: cy - slashHeight / 2))
    core.line(to: NSPoint(x: cx + slashSlant, y: cy + slashHeight / 2))
    NSColor(red: 0.65, green: 0.97, blue: 1.0, alpha: 0.9).setStroke()
    core.stroke()

    // Layer 4: white-hot center
    let hotCore = NSBezierPath()
    hotCore.lineWidth = size * 0.022
    hotCore.lineCapStyle = .round
    hotCore.move(to: NSPoint(x: cx - slashSlant, y: cy - slashHeight / 2))
    hotCore.line(to: NSPoint(x: cx + slashSlant, y: cy + slashHeight / 2))
    NSColor(red: 0.9, green: 1.0, blue: 1.0, alpha: 0.95).setStroke()
    hotCore.stroke()

    // Small sparkle dot at top end of slash
    let dotX = cx + slashSlant
    let dotY = cy + slashHeight / 2
    let dotR = size * 0.018
    let sparkDot = NSRect(x: dotX - dotR + size * 0.04, y: dotY - dotR + size * 0.02, width: dotR * 2, height: dotR * 2)
    NSColor(red: 0.7, green: 1.0, blue: 1.0, alpha: 0.8).setFill()
    NSBezierPath(ovalIn: sparkDot).fill()

    // Small sparkle dot at bottom end of slash
    let dot2X = cx - slashSlant
    let dot2Y = cy - slashHeight / 2
    let dot2R = size * 0.012
    let sparkDot2 = NSRect(x: dot2X - dot2R - size * 0.03, y: dot2Y - dot2R - size * 0.02, width: dot2R * 2, height: dot2R * 2)
    NSColor(red: 0.7, green: 1.0, blue: 1.0, alpha: 0.5).setFill()
    NSBezierPath(ovalIn: sparkDot2).fill()

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
