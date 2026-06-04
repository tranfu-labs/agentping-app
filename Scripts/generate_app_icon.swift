import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")
let iconset = assets.appendingPathComponent("AgentPing.iconset")
let icns = assets.appendingPathComponent("AgentPingIcon.icns")

try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let scaleFiles: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let rect = NSRect(x: size * 0.092, y: size * 0.092, width: size * 0.816, height: size * 0.816)
    let radius = size * 0.19
    let base = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: [
        NSColor(red: 0.99, green: 0.20, blue: 0.24, alpha: 1),
        NSColor(red: 0.76, green: 0.07, blue: 0.11, alpha: 1),
    ])?.draw(in: base, angle: -35)

    NSColor(calibratedWhite: 1, alpha: 0.16).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: rect.minX + size * 0.055, y: rect.maxY - size * 0.18, width: rect.width - size * 0.11, height: size * 0.06),
        xRadius: size * 0.03,
        yRadius: size * 0.03
    ).fill()

    NSColor(calibratedWhite: 0, alpha: 0.16).setStroke()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).stroke()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.2)
    shadow.shadowBlurRadius = size * 0.025
    shadow.shadowOffset = NSSize(width: size * 0.018, height: -size * 0.018)
    shadow.set()

    let markFont = NSFont.systemFont(ofSize: size * 0.62, weight: .heavy)
    let mark = NSAttributedString(
        string: "P",
        attributes: [
            .font: markFont,
            .foregroundColor: NSColor.white,
            .kern: -size * 0.028,
        ]
    )
    let markSize = mark.size()

    let context = NSGraphicsContext.current?.cgContext
    context?.saveGState()
    context?.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.22, d: 1, tx: size * 0.09, ty: 0))
    mark.draw(at: NSPoint(
        x: (size - markSize.width) / 2 + size * 0.035,
        y: (size - markSize.height) / 2 - size * 0.012
    ))
    context?.restoreGState()

    NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
    let speedPath = NSBezierPath()
    speedPath.move(to: NSPoint(x: size * 0.58, y: size * 0.315))
    speedPath.line(to: NSPoint(x: size * 0.79, y: size * 0.315))
    speedPath.lineWidth = max(2, size * 0.035)
    speedPath.lineCapStyle = .round
    speedPath.stroke()

    return image
}

func writePNG(_ image: NSImage, to url: URL, pixels: CGFloat) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AgentPingIcon", code: 1)
    }
    try png.write(to: url)
}

for (file, pixels) in scaleFiles {
    try writePNG(drawIcon(size: pixels), to: iconset.appendingPathComponent(file), pixels: pixels)
}

try? FileManager.default.removeItem(at: icns)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "AgentPingIcon", code: Int(process.terminationStatus))
}

print(icns.path)
