import AppKit
import Foundation

// House style shared with Tessellate: dark gradient rounded plate, hairline rim,
// white geometric shapes at descending alpha. Cargo's mark is a stack of three
// container slabs — the thing the app moves.

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-cargo-icon.swift <iconset-directory>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let iconSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fputs("could not create bitmap\n", stderr)
        exit(1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    let ctx = graphicsContext.cgContext
    let s = CGFloat(pixels) / 1024
    ctx.scaleBy(x: s, y: s)

    // Plate
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    platePath.addClip()
    let colors = [
        NSColor(calibratedWhite: 0.28, alpha: 1).cgColor,
        NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: []
    )
    ctx.restoreGState()

    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    platePath.lineWidth = 4
    platePath.stroke()

    // Three container slabs, stacked; the top one slightly offset like a crane just set it down.
    let field = CGRect(x: 250, y: 250, width: 524, height: 524)
    let gap: CGFloat = 34
    let radius: CGFloat = 26
    let slabHeight = (field.height - gap * 2) / 3

    func slab(_ rect: CGRect, alpha: CGFloat) {
        NSColor(calibratedWhite: 1, alpha: alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
    slab(CGRect(x: field.minX, y: field.minY, width: field.width, height: slabHeight), alpha: 0.97)
    slab(CGRect(x: field.minX, y: field.minY + slabHeight + gap, width: field.width, height: slabHeight), alpha: 0.72)
    slab(
        CGRect(x: field.minX + 62, y: field.minY + (slabHeight + gap) * 2, width: field.width - 124, height: slabHeight),
        alpha: 0.52
    )

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

for iconSize in iconSizes {
    let bitmap = drawIcon(pixels: iconSize.pixels)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fputs("could not encode PNG\n", stderr)
        exit(1)
    }
    try pngData.write(to: outputDirectory.appendingPathComponent(iconSize.name))
}
