import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: generate-icon.swift ICONSET_DIR OUTPUT_ICNS\n", stderr)
    exit(EXIT_FAILURE)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let fileManager = FileManager.default

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let representations: [(pixels: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for representation in representations {
    let size = representation.pixels
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconError.couldNotCreateBitmap(size)
    }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let inset = CGFloat(size) * 0.035
    let iconRect = NSRect(
        x: inset,
        y: inset,
        width: CGFloat(size) - inset * 2,
        height: CGFloat(size) - inset * 2
    )
    let background = NSBezierPath(
        roundedRect: iconRect,
        xRadius: CGFloat(size) * 0.22,
        yRadius: CGFloat(size) * 0.22
    )
    let gradient = NSGradient(
        starting: NSColor(red: 0.06, green: 0.63, blue: 0.68, alpha: 1),
        ending: NSColor(red: 0.20, green: 0.18, blue: 0.55, alpha: 1)
    )
    gradient?.draw(in: background, angle: -45)

    NSColor.white.withAlphaComponent(0.22).setStroke()
    background.lineWidth = max(1, CGFloat(size) * 0.012)
    background.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: CGFloat(size) * 0.34, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
        .kern: -CGFloat(size) * 0.018,
    ]
    let textRect = NSRect(
        x: 0,
        y: CGFloat(size) * 0.305,
        width: CGFloat(size),
        height: CGFloat(size) * 0.42
    )
    NSString(string: "AS").draw(in: textRect, withAttributes: attributes)

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.couldNotEncodePNG(size)
    }
    try data.write(to: iconsetURL.appendingPathComponent(representation.name), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw IconError.iconutilFailed(process.terminationStatus)
}

enum IconError: LocalizedError {
    case couldNotCreateBitmap(Int)
    case couldNotEncodePNG(Int)
    case iconutilFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .couldNotCreateBitmap(size): "Could not create the \(size)-pixel icon bitmap."
        case let .couldNotEncodePNG(size): "Could not encode the \(size)-pixel icon bitmap."
        case let .iconutilFailed(status): "iconutil exited with status \(status)."
        }
    }
}
