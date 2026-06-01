#!/usr/bin/swift
// generate_icons.swift
// Run from the project root: swift Scripts/generate_icons.swift
// Generates MacLauncher Remote app icons for macOS and iOS.

import AppKit
import Foundation

// MARK: - Drawing

func drawIcon(in ctx: CGContext, size s: CGFloat) {
    let cs = CGColorSpaceCreateDeviceRGB()

    // ── Rounded-rect clip ──────────────────────────────────────────────
    let radius = s * 0.225
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // ── Background gradient (top-left bright → bottom-right deep) ─────
    // Bright blue  #3B82F6  (0.231, 0.510, 0.965)
    // Deep navy    #1E3A8A  (0.118, 0.227, 0.541)
    let c1 = CGColor(colorSpace: cs, components: [0.231, 0.510, 0.965, 1.0])!
    let c2 = CGColor(colorSpace: cs, components: [0.118, 0.227, 0.541, 1.0])!
    let gradient = CGGradient(colorsSpace: cs, colors: [c1, c2] as CFArray,
                              locations: [0.0, 1.0])!
    // In CGContext, y=0 is bottom, y=s is top.
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0,   y: s),   // top-left
                           end:   CGPoint(x: s,   y: 0),   // bottom-right
                           options: [])

    // ── Colors ────────────────────────────────────────────────────────
    let w100 = CGColor(colorSpace: cs, components: [1, 1, 1, 1.00])!
    let w070 = CGColor(colorSpace: cs, components: [1, 1, 1, 0.70])!
    let w040 = CGColor(colorSpace: cs, components: [1, 1, 1, 0.40])!

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // ── Signal arc layout ─────────────────────────────────────────────
    // Arc center sits slightly below icon center so the pole+base
    // have room below and arcs fill the upper portion.
    let cx        = s * 0.500
    let arcCY     = s * 0.475
    let arcCenter = CGPoint(x: cx, y: arcCY)

    let r1 = s * 0.148   // inner  arc radius
    let r2 = s * 0.228   // middle arc radius
    let r3 = s * 0.308   // outer  arc radius

    // Arcs open upward: clockwise from 150° to 30° through 90° (up).
    // CGContext convention: angles are CCW from +x axis; clockwise=true → CW direction.
    let aStart = CGFloat.pi * 5.0 / 6.0   // 150°
    let aEnd   = CGFloat.pi       / 6.0   // 30°

    // Line widths — clamp so thin at small sizes still visible
    let lw1 = max(1.2, s * 0.054)
    let lw2 = max(1.2, s * 0.047)
    let lw3 = max(1.2, s * 0.040)

    // Draw outer → inner (so inner is on top)
    ctx.setStrokeColor(w040);  ctx.setLineWidth(lw3)
    ctx.addArc(center: arcCenter, radius: r3, startAngle: aStart, endAngle: aEnd, clockwise: true)
    ctx.strokePath()

    ctx.setStrokeColor(w070);  ctx.setLineWidth(lw2)
    ctx.addArc(center: arcCenter, radius: r2, startAngle: aStart, endAngle: aEnd, clockwise: true)
    ctx.strokePath()

    ctx.setStrokeColor(w100);  ctx.setLineWidth(lw1)
    ctx.addArc(center: arcCenter, radius: r1, startAngle: aStart, endAngle: aEnd, clockwise: true)
    ctx.strokePath()

    // ── Center dot ────────────────────────────────────────────────────
    let dotR = max(3.0, s * 0.058)
    ctx.setFillColor(w100)
    ctx.addEllipse(in: CGRect(x: arcCenter.x - dotR, y: arcCenter.y - dotR,
                              width: dotR * 2, height: dotR * 2))
    ctx.fillPath()

    // Pole and base are only visible ≥ 32px
    guard s >= 32 else { return }

    // ── Antenna pole ──────────────────────────────────────────────────
    let poleW   = max(2.0, s * 0.054)
    let poleTop = arcCenter.y - dotR          // connects to bottom of dot
    let poleBot = s * 0.200                   // 20% from bottom
    let poleH   = poleTop - poleBot

    if poleH > 0 {
        let polePath = CGPath(
            roundedRect: CGRect(x: cx - poleW / 2, y: poleBot, width: poleW, height: poleH),
            cornerWidth: poleW / 2, cornerHeight: poleW / 2, transform: nil)
        ctx.setFillColor(w100)
        ctx.addPath(polePath)
        ctx.fillPath()
    }

    // ── Base (horizontal bar, Mac-stand look) ─────────────────────────
    let baseW = s * 0.430
    let baseH = max(4.0, s * 0.052)
    let baseY = s * 0.120                     // 12% from bottom

    let basePath = CGPath(
        roundedRect: CGRect(x: cx - baseW / 2, y: baseY, width: baseW, height: baseH),
        cornerWidth: baseH / 2, cornerHeight: baseH / 2, transform: nil)
    ctx.setFillColor(w100)
    ctx.addPath(basePath)
    ctx.fillPath()
}

// MARK: - PNG helper

func makePNG(pixelSize: Int) -> Data? {
    let s = CGFloat(pixelSize)
    guard let ctx = CGContext(
        data: nil, width: pixelSize, height: pixelSize,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    drawIcon(in: ctx, size: s)

    guard let cgImage = ctx.makeImage() else { return nil }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: s, height: s))
    guard let tiff = nsImage.tiffRepresentation,
          let bmp  = NSBitmapImageRep(data: tiff),
          let png  = bmp.representation(using: .png, properties: [:])
    else { return nil }
    return png
}

// MARK: - Main

let cwd       = FileManager.default.currentDirectoryPath
let macDir    = "\(cwd)/MacApp/Resources/Assets.xcassets/AppIcon.appiconset"
let iOSDir    = "\(cwd)/iOSApp/Resources/Assets.xcassets/AppIcon.appiconset"

let macFiles: [(String, Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png",1024),
]
let iOSFiles: [(String, Int)] = [
    ("icon_1024.png", 1024),
]

print("MacLauncher Remote — Generating icons…\n")

// Cache by pixel size to avoid re-generating the same resolution twice
var pngCache: [Int: Data] = [:]

func save(dir: String, name: String, pixels: Int) {
    let png: Data
    if let hit = pngCache[pixels] {
        png = hit
    } else if let gen = makePNG(pixelSize: pixels) {
        pngCache[pixels] = gen
        png = gen
    } else {
        print("  ✗  \(name)  — generation failed"); return
    }
    let url = URL(fileURLWithPath: "\(dir)/\(name)")
    do {
        try png.write(to: url)
        print("  ✓  \(name)  (\(pixels)px)")
    } catch {
        print("  ✗  \(name)  — \(error)")
    }
}

print("macOS icons:")
for (name, px) in macFiles { save(dir: macDir, name: name, pixels: px) }

print("\niOS icons:")
for (name, px) in iOSFiles { save(dir: iOSDir, name: name, pixels: px) }

print("\nDone ✓")
