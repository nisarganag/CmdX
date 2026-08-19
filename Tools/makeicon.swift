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

    // Rounded-rect background, matching the macOS icon silhouette.
    let inset = dim * 0.06
    let rect = CGRect(x: inset, y: inset, width: dim - inset * 2, height: dim - inset * 2)
    let radius = dim * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()

    NSGradient(colors: [
        NSColor(calibratedRed: 0.29, green: 0.53, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.26, blue: 0.72, alpha: 1),
    ])?.draw(in: rect, angle: -90)

    // White scissors glyph, centred.
    let config = NSImage.SymbolConfiguration(pointSize: dim * 0.46, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        let target = CGRect(
            x: (dim - size.width) / 2,
            y: (dim - size.height) / 2,
            width: size.width,
            height: size.height)
        // Tint the glyph white on its own isolated transparent canvas, then
        // composite the result onto the icon with plain source-over.
        //
        // Flooding white via sourceAtop directly onto `target` (as drawn on the
        // icon canvas) does not isolate the glyph's shape: sourceAtop only
        // preserves shape where destination alpha is non-uniform, and by this
        // point the background gradient has already made the destination alpha
        // 1 everywhere under `target`, so the flood paints the entire bounding
        // rect solid white instead of just the scissors strokes. Doing the
        // tint on a fresh transparent NSImage first (alpha 0 outside the glyph)
        // keeps the recolor scoped to the glyph's own shape.
        let whiteSymbol = NSImage(size: size)
        whiteSymbol.lockFocus()
        symbol.draw(in: CGRect(origin: .zero, size: size))
        NSColor.white.set()
        CGRect(origin: .zero, size: size).fill(using: .sourceAtop)
        whiteSymbol.unlockFocus()

        whiteSymbol.draw(in: target)
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
