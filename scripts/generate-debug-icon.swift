import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Preserve the release wordmark and add a development badge at every macOS icon size.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
let outputURL = root.appendingPathComponent("Assets.xcassets/AppIconDebug.appiconset")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot load the release icon at \(sourceURL.path)")
}
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

var entries: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let size = CGFloat(pixels)
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { fatalError("Cannot create a \(pixels)px icon context") }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        // A single letter stays readable at small sizes; larger icons show the full badge.
        let compact = pixels <= 64
        let badge = CGRect(
            x: size * 0.57, y: size * (compact ? 0.67 : 0.74),
            width: size * 0.32, height: size * (compact ? 0.24 : 0.15)
        )
        context.setFillColor(CGColor(red: 0.85, green: 0.63, blue: 0.31, alpha: 1))
        context.addPath(CGPath(roundedRect: badge, cornerWidth: size * 0.035, cornerHeight: size * 0.035, transform: nil))
        context.fillPath()

        let text = NSAttributedString(string: compact ? "D" : "DEV", attributes: [
            .font: NSFont.systemFont(ofSize: size * (compact ? 0.18 : 0.095), weight: .semibold),
            .foregroundColor: NSColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        context.textPosition = CGPoint(x: badge.midX - width / 2, y: badge.midY - (ascent - descent) / 2)
        CTLineDraw(line, context)

        guard let rendered = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                outputURL.appendingPathComponent(filename) as CFURL, UTType.png.identifier as CFString, 1, nil
              ) else { fatalError("Cannot write \(filename)") }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot finish \(filename)") }
        entries.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": filename])
    }
}

let catalog: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
let data = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
try (data + Data("\n".utf8)).write(to: outputURL.appendingPathComponent("Contents.json"))
