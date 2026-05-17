import AppKit
import CoreGraphics
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("MacCleaner/Resources", isDirectory: true)
let appIconSetURL = resourcesURL.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let iconSetURL = resourcesURL.appendingPathComponent("Images.iconset", isDirectory: true)

try FileManager.default.createDirectory(at: appIconSetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)

struct IconRenderConfig {
    let size: Int
    let includeMacPlate: Bool
}

func makeColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawIcon(size: Int, includeMacPlate: Bool) -> NSImage {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [.alphaFirst],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to create bitmap")
    }

    let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext

    guard let context = graphicsContext?.cgContext else {
        fatalError("Unable to create drawing context")
    }

    let scale = CGFloat(size) / 1024
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    context.clear(bounds)

    let backgroundRect = bounds.insetBy(dx: 42 * scale, dy: 42 * scale)
    let backgroundPath = CGPath(
        roundedRect: backgroundRect,
        cornerWidth: 222 * scale,
        cornerHeight: 222 * scale,
        transform: nil
    )

    let backgroundGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            makeColor(24, 122, 238).copy(alpha: 1)!,
            makeColor(40, 199, 162).copy(alpha: 1)!
        ] as CFArray,
        locations: [0, 1]
    )!

    context.saveGState()
    context.addPath(backgroundPath)
    context.clip()
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: backgroundRect.minX, y: backgroundRect.maxY),
        end: CGPoint(x: backgroundRect.maxX, y: backgroundRect.minY),
        options: []
    )

    let shineGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            makeColor(255, 255, 255, 0.26),
            makeColor(255, 255, 255, 0.02)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        shineGradient,
        start: CGPoint(x: backgroundRect.minX, y: backgroundRect.maxY),
        end: CGPoint(x: backgroundRect.maxX, y: backgroundRect.midY),
        options: []
    )
    context.restoreGState()

    context.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 42 * scale, color: makeColor(5, 30, 63, 0.28))
    context.addPath(backgroundPath)
    context.setStrokeColor(makeColor(255, 255, 255, 0.35))
    context.setLineWidth(12 * scale)
    context.strokePath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    if includeMacPlate {
        let plateRect = CGRect(x: 214 * scale, y: 254 * scale, width: 596 * scale, height: 410 * scale)
        let platePath = CGPath(
            roundedRect: plateRect,
            cornerWidth: 72 * scale,
            cornerHeight: 72 * scale,
            transform: nil
        )
        context.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 32 * scale, color: makeColor(4, 37, 78, 0.25))
        context.addPath(platePath)
        context.setFillColor(makeColor(244, 250, 255, 0.94))
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        context.addPath(platePath)
        context.setStrokeColor(makeColor(255, 255, 255, 0.75))
        context.setLineWidth(9 * scale)
        context.strokePath()

        let slotRect = CGRect(x: 326 * scale, y: 552 * scale, width: 372 * scale, height: 34 * scale)
        context.addPath(CGPath(roundedRect: slotRect, cornerWidth: 17 * scale, cornerHeight: 17 * scale, transform: nil))
        context.setFillColor(makeColor(20, 70, 118, 0.16))
        context.fillPath()
    }

    let sparkCenter = CGPoint(x: 620 * scale, y: 518 * scale)
    let sparkLong = 176 * scale
    let sparkShort = 58 * scale
    let sparkPath = CGMutablePath()
    sparkPath.move(to: CGPoint(x: sparkCenter.x, y: sparkCenter.y + sparkLong))
    sparkPath.addQuadCurve(to: CGPoint(x: sparkCenter.x + sparkShort, y: sparkCenter.y + sparkShort), control: CGPoint(x: sparkCenter.x + 20 * scale, y: sparkCenter.y + 86 * scale))
    sparkPath.addQuadCurve(to: CGPoint(x: sparkCenter.x + sparkLong, y: sparkCenter.y), control: CGPoint(x: sparkCenter.x + 86 * scale, y: sparkCenter.y + 20 * scale))
    sparkPath.addQuadCurve(to: CGPoint(x: sparkCenter.x + sparkShort, y: sparkCenter.y - sparkShort), control: CGPoint(x: sparkCenter.x + 86 * scale, y: sparkCenter.y - 20 * scale))
    sparkPath.addQuadCurve(to: CGPoint(x: sparkCenter.x, y: sparkCenter.y - sparkLong), control: CGPoint(x: sparkCenter.x + 20 * scale, y: sparkCenter.y - 86 * scale))
    sparkPath.addQuadCurve(to: CGPoint(x: sparkCenter.x - sparkShort, y: sparkCenter.y - sparkShort), control: CGPoint(x: sparkCenter.x - 20 * scale, y: sparkCenter.y - 86 * scale))
    sparkPath.addQuadCurve(to: CGPoint(x: sparkCenter.x - sparkLong, y: sparkCenter.y), control: CGPoint(x: sparkCenter.x - 86 * scale, y: sparkCenter.y - 20 * scale))
    sparkPath.addQuadCurve(to: CGPoint(x: sparkCenter.x - sparkShort, y: sparkCenter.y + sparkShort), control: CGPoint(x: sparkCenter.x - 86 * scale, y: sparkCenter.y + 20 * scale))
    sparkPath.closeSubpath()

    context.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 20 * scale, color: makeColor(12, 99, 151, 0.22))
    context.addPath(sparkPath)
    context.setFillColor(makeColor(255, 255, 255, 0.98))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    let smallSparkCenter = CGPoint(x: 412 * scale, y: 410 * scale)
    for radius in [36, 18] {
        let r = CGFloat(radius) * scale
        context.addEllipse(in: CGRect(x: smallSparkCenter.x - r, y: smallSparkCenter.y - r, width: 2 * r, height: 2 * r))
        context.setFillColor(makeColor(255, 255, 255, radius == 36 ? 0.32 : 0.92))
        context.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(bitmap)
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        fatalError("Unable to encode PNG for \(url.path)")
    }

    try pngData.write(to: url)
}

let appIconEntries: [(String, Int, String)] = [
    ("16x16", 16, "1x"),
    ("16x16", 32, "2x"),
    ("32x32", 32, "1x"),
    ("32x32", 64, "2x"),
    ("128x128", 128, "1x"),
    ("128x128", 256, "2x"),
    ("256x256", 256, "1x"),
    ("256x256", 512, "2x"),
    ("512x512", 512, "1x"),
    ("512x512", 1024, "2x")
]

var contentsImages: [[String: String]] = []

for (idiomSize, pixelSize, scale) in appIconEntries {
    let filename = "maccleaner-icon-\(pixelSize).png"
    let image = drawIcon(size: pixelSize, includeMacPlate: pixelSize >= 64)
    try writePNG(image, to: appIconSetURL.appendingPathComponent(filename))
    contentsImages.append([
        "filename": filename,
        "idiom": "mac",
        "scale": scale,
        "size": idiomSize
    ])
}

let contents: [String: Any] = [
    "images": contentsImages,
    "info": [
        "author": "xcode",
        "version": 1
    ]
]
let contentsData = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try contentsData.write(to: appIconSetURL.appendingPathComponent("Contents.json"))

let iconSetEntries: [(String, Int)] = [
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

for (filename, pixelSize) in iconSetEntries {
    let image = drawIcon(size: pixelSize, includeMacPlate: pixelSize >= 64)
    try writePNG(image, to: iconSetURL.appendingPathComponent(filename))
}

try writePNG(drawIcon(size: 256, includeMacPlate: true), to: resourcesURL.appendingPathComponent("SidebarIcon.png"))
