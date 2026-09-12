import AppKit
import Foundation

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

for iconSize in iconSizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: iconSize.pixels,
        pixelsHigh: iconSize.pixels,
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

    let canvas = CGFloat(iconSize.pixels)
    let scale = canvas / 1024
    let point = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * scale, y: y * scale) }

    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvas, height: canvas)).fill()

    let background = NSBezierPath(
        roundedRect: NSRect(x: 76 * scale, y: 76 * scale, width: 872 * scale, height: 872 * scale),
        xRadius: 190 * scale,
        yRadius: 190 * scale
    )
    NSColor(calibratedRed: 0.12, green: 0.31, blue: 0.72, alpha: 1).setFill()
    background.fill()

    let cubeStroke = NSBezierPath()
    cubeStroke.lineWidth = 64 * scale
    cubeStroke.lineJoinStyle = .round
    cubeStroke.lineCapStyle = .round

    cubeStroke.move(to: point(512, 760))
    cubeStroke.line(to: point(780, 610))
    cubeStroke.line(to: point(512, 460))
    cubeStroke.line(to: point(244, 610))
    cubeStroke.close()

    cubeStroke.move(to: point(244, 610))
    cubeStroke.line(to: point(244, 370))
    cubeStroke.line(to: point(512, 220))
    cubeStroke.line(to: point(780, 370))
    cubeStroke.line(to: point(780, 610))

    cubeStroke.move(to: point(512, 460))
    cubeStroke.line(to: point(512, 220))

    NSColor.white.setStroke()
    cubeStroke.stroke()
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
        fputs("could not encode PNG\n", stderr)
        exit(1)
    }
    try pngData.write(to: outputDirectory.appendingPathComponent(iconSize.name))
}
