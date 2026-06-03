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

    let rect = NSRect(x: size * 0.094, y: size * 0.094, width: size * 0.812, height: size * 0.812)
    let radius = size * 0.184
    let base = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor(red: 0.902, green: 0.192, blue: 0.22, alpha: 1).setFill()
    base.fill()

    let mark = NSAttributedString(
        string: "P",
        attributes: [
            .font: NSFont.systemFont(ofSize: size * 0.61, weight: .heavy),
            .foregroundColor: NSColor.white,
            .kern: -size * 0.018,
        ]
    )
    let markSize = mark.size()
    mark.draw(at: NSPoint(
        x: (size - markSize.width) / 2 + size * 0.016,
        y: (size - markSize.height) / 2 - size * 0.014
    ))

    NSColor(calibratedWhite: 0.05, alpha: 0.22).setFill()
    NSBezierPath(
        ovalIn: NSRect(x: size * 0.642, y: size * 0.662, width: size * 0.074, height: size * 0.074)
    ).fill()

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
