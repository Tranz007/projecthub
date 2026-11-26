#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// Command Orbit: a large command chevron and a distinct project hub dot.
// Draw every icon size from the same geometry so small Dock and sidebar sizes stay crisp.
private let canvas: CGFloat = 1024
private let colorSpace = CGColorSpaceCreateDeviceRGB()
private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let resources = root.appendingPathComponent("Resources", isDirectory: true)
private let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("ProjectHub-AppIcon-\(UUID().uuidString).iconset", isDirectory: true)

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

private func gradient(_ colors: [CGColor], locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
}

private func render(size: Int) throws -> Data {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }

    context.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let tile = CGPath(roundedRect: CGRect(x: 48, y: 48, width: 928, height: 928),
                      cornerWidth: 222, cornerHeight: 222, transform: nil)
    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.drawLinearGradient(
        gradient([color(24, 43, 77), color(8, 16, 36)], locations: [0, 1]),
        start: CGPoint(x: 280, y: 976), end: CGPoint(x: 800, y: 48),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()

    context.addPath(tile)
    context.setStrokeColor(color(84, 121, 174, 0.48))
    context.setLineWidth(7)
    context.strokePath()

    // The open chevron leaves ample space for the hub dot at 35 × 35 px.
    context.saveGState()
    context.move(to: CGPoint(x: 330, y: 715))
    context.addLine(to: CGPoint(x: 708, y: 512))
    context.addLine(to: CGPoint(x: 330, y: 309))
    context.setLineWidth(116)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gradient([color(42, 211, 252), color(20, 100, 242)], locations: [0, 1]),
        start: CGPoint(x: 270, y: 780), end: CGPoint(x: 750, y: 270),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()

    let hub = CGPath(ellipseIn: CGRect(x: 288, y: 434, width: 156, height: 156), transform: nil)
    context.saveGState()
    context.addPath(hub)
    context.clip()
    context.drawLinearGradient(
        gradient([color(203, 255, 61), color(129, 228, 24)], locations: [0, 1]),
        start: CGPoint(x: 340, y: 590), end: CGPoint(x: 410, y: 434),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()

    guard let image = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    return data
}

private let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]

do {
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }

    for (size, name) in sizes {
        try render(size: size).write(to: iconset.appendingPathComponent(name))
    }
    try render(size: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    print("Generated Resources/AppIcon.png and Resources/AppIcon.icns")
} catch {
    fputs("Icon generation failed: \(error)\n", stderr)
    exit(1)
}
