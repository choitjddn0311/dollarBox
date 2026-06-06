#!/usr/bin/env swift
import AppKit
import CoreGraphics

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(pixels)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return rep }

    let rect = CGRect(origin: .zero, size: CGSize(width: s, height: s))
    let corner = s * 0.22

    // ── Background gradient ─────────────────────────────────────────────
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    let cs = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        CGColor(red: 0.04, green: 0.11, blue: 0.22, alpha: 1),
        CGColor(red: 0.05, green: 0.25, blue: 0.38, alpha: 1)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: cs, colors: gradColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: s, y: 0),
                           options: [])

    // ── Glow ────────────────────────────────────────────────────────────
    let glowColors = [
        CGColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 0.13),
        CGColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 0.0)
    ] as CFArray
    let radial = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(radial,
                           startCenter: CGPoint(x: s * 0.5, y: s * 0.52), startRadius: 0,
                           endCenter:   CGPoint(x: s * 0.5, y: s * 0.52), endRadius: s * 0.42,
                           options: [])

    // ── Dollar sign ──────────────────────────────────────────────────────
    let fontSize = s * 0.52
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: fontSize),
        .foregroundColor: NSColor.white
    ]
    let str = "$" as NSString
    let strSize = str.size(withAttributes: attrs)
    let strRect = CGRect(
        x: (s - strSize.width)  / 2 + s * 0.01,
        y: (s - strSize.height) / 2 + s * 0.02,
        width: strSize.width,
        height: strSize.height
    )
    str.draw(in: strRect, withAttributes: attrs)

    // ── ₩ label ──────────────────────────────────────────────────────────
    let subSize2 = s * 0.15
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: subSize2, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.5)
    ]
    let sub = "₩" as NSString
    let subSz = sub.size(withAttributes: subAttrs)
    sub.draw(in: CGRect(
        x: s - subSz.width - s * 0.10,
        y: s * 0.10,
        width: subSz.width,
        height: subSz.height
    ), withAttributes: subAttrs)

    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed: \(path)"); return
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("✓ \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

let outDir = "ExchangeRateApp/Assets.xcassets/AppIcon.appiconset"
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16.png",   16),
    ("icon_32.png",   32),
    ("icon_64.png",   64),
    ("icon_128.png",  128),
    ("icon_256.png",  256),
    ("icon_512.png",  512),
    ("icon_1024.png", 1024)
]

for item in sizes {
    savePNG(drawIcon(pixels: item.px), to: "\(outDir)/\(item.name)")
}

print("Done.")
