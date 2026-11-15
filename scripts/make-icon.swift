#!/usr/bin/swift
// Generates Resources/AppIcon.icns from an SF Symbol on a gradient.
//
//   swift scripts/make-icon.swift
//
// The icon is drawn at every size macOS expects, so the menu bar app looks
// finished in the Dock / Launchpad / Applications folder.

import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources")
let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

func renderIcon(size: CGFloat) -> Data? {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = body.width * 0.2237

    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    shape.addClip()

    let gradient = NSGradient(colors: [color(0x3B7EA1), color(0x1B2A41)])!
    gradient.draw(in: body, angle: -90)

    // soft highlight on top
    let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    highlight.draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

    // the bolt (palette colours, a template symbol would be drawn black)
    let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        symbol.isTemplate = false
        let symbolSize = NSSize(width: symbol.size.width, height: symbol.size.height)
        let scale = (size * 0.52) / max(symbolSize.width, symbolSize.height)
        let drawSize = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
        let origin = NSPoint(x: body.midX - drawSize.width / 2, y: body.midY - drawSize.height / 2)
        symbol.draw(in: NSRect(origin: origin, size: drawSize),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return nil }
    return png
}

let variants: [(name: String, pixels: Int, scale: Int)] = [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 32, 2),
    ("icon_32x32", 32, 1), ("icon_32x32@2x", 64, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 256, 2),
    ("icon_256x256", 256, 1), ("icon_256x256@2x", 512, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 1024, 2)
]

for variant in variants {
    guard let png = renderIcon(size: CGFloat(variant.pixels)) else {
        FileHandle.standardError.write(Data("cannot render \(variant.name)\n".utf8))
        exit(1)
    }
    let target = iconset.appendingPathComponent("\(variant.name).png")
    try png.write(to: target)
}

let icns = outputDirectory.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()

try? FileManager.default.removeItem(at: iconset)
print("wrote \(icns.path)")
