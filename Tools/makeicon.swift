import AppKit
import Foundation

// Renders AppIcon.iconset from the SF Symbol "scissors" — no external assets.
// Usage: swift Tools/makeicon.swift <output.iconset>

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"
let out = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// iconutil requires these exact filenames.
let variants: [(pixels: Int, names: [String])] = [
    (16,   ["icon_16x16.png"]),
    (32,   ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64,   ["icon_32x32@2x.png"]),
    (128,  ["icon_128x128.png"]),
    (256,  ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512,  ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"]),
]

/// Apple's icon silhouette is a superellipse, not a circular-radius rounded
/// rect. Circular corners are the single most obvious tell that an icon was not
/// made for macOS — they bulge where Apple's curve stays taut.
func squircle(in rect: CGRect, exponent: Double = 5.0) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720

    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * Double.pi
        let ct = cos(t), st = sin(t)
        let x = pow(abs(ct), 2.0 / exponent) * (ct < 0 ? -1 : 1) * a
        let y = pow(abs(st), 2.0 / exponent) * (st < 0 ? -1 : 1) * b
        let point = NSPoint(x: cx + x, y: cy + y)
        if i == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    return path
}

func render(pixels: Int) -> Data? {
    let dim = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    // macOS icons sit inside their canvas with real margin, and cast a soft
    // shadow onto it. Filling the whole square is another non-native tell.
    let margin = dim * 0.095
    let body = CGRect(x: margin, y: margin * 1.25,
                      width: dim - margin * 2, height: dim - margin * 2)
    let shape = squircle(in: body)

    if pixels >= 64 {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
        shadow.shadowBlurRadius = dim * 0.035
        shadow.shadowOffset = NSSize(width: 0, height: -dim * 0.018)
        shadow.set()
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()

    NSGradient(colors: [
        NSColor(calibratedWhite: 0.24, alpha: 1),
        NSColor(calibratedWhite: 0.075, alpha: 1),
    ])?.draw(in: body, angle: -90)

    // A bright sliver along the top edge reads as a lit surface and gives the
    // face some curvature instead of leaving it a flat swatch.
    NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 0.13),
        NSColor(calibratedWhite: 1, alpha: 0.0),
    ])?.draw(in: CGRect(x: body.minX, y: body.midY,
                        width: body.width, height: body.height / 2), angle: -90)

    NSGraphicsContext.restoreGraphicsState()

    // Hairline rim, so the icon holds an edge against a light background.
    NSColor(calibratedWhite: 1, alpha: 0.15).setStroke()
    shape.lineWidth = max(1, dim * 0.004)
    shape.stroke()

    // Scissors glyph, centred on the body rather than the canvas.
    let config = NSImage.SymbolConfiguration(pointSize: dim * 0.40, weight: .regular)
    if let symbol = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        let target = CGRect(
            x: body.midX - size.width / 2,
            y: body.midY - size.height / 2,
            width: size.width,
            height: size.height)

        // Tint on an isolated transparent canvas. Flooding sourceAtop directly
        // onto the icon would fill the whole glyph rect, because the gradient
        // underneath is already opaque and leaves nothing for it to key against.
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        symbol.draw(in: CGRect(origin: .zero, size: size))
        NSColor.white.set()
        CGRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        NSGraphicsContext.saveGraphicsState()
        if pixels >= 64 {
            let glyphShadow = NSShadow()
            glyphShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.55)
            glyphShadow.shadowBlurRadius = dim * 0.018
            glyphShadow.shadowOffset = NSSize(width: 0, height: -dim * 0.008)
            glyphShadow.set()
        }
        tinted.draw(in: target)
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for variant in variants {
    guard let data = render(pixels: variant.pixels) else {
        FileHandle.standardError.write("failed to render \(variant.pixels)px\n".data(using: .utf8)!)
        exit(1)
    }
    for name in variant.names {
        try? data.write(to: out.appendingPathComponent(name))
    }
}

print("wrote \(out.path)")
