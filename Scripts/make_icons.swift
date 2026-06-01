#!/usr/bin/env swift
// Generates MacLauncher Remote app icons for macOS and iOS
// Design: deep blue-purple gradient + Mac screen + wireless signal arcs

import AppKit
import CoreGraphics

// MARK: - Color helpers

func cgColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: a)
}

// MARK: - Draw icon

func drawIcon(size: CGFloat, forMac: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = forMac ? size * 0.22 : 0   // macOS 아이콘: 직접 둥근 모서리, iOS: 시스템이 적용

    // -- 1. 배경 그라디언트 --
    if forMac {
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(path)
        ctx.clip()
    }

    let gradColors = [
        cgColor(14, 22, 100),   // 좌상단: 딥 인디고
        cgColor(32, 12, 88),    // 우하단: 딥 퍼플
    ] as CFArray
    let locs: [CGFloat] = [0, 1]
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: locs)!
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: [])

    // -- 2. 앰비언트 글로우 (퍼플) --
    let glowCenter = CGPoint(x: size * 0.65, y: size * 0.65)
    let glowRadius = size * 0.55
    let glowColors = [cgColor(120, 40, 200, 0.30), cgColor(60, 10, 130, 0)] as CFArray
    let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: locs)!
    ctx.drawRadialGradient(glowGradient,
        startCenter: glowCenter, startRadius: 0,
        endCenter: glowCenter, endRadius: glowRadius,
        options: [])

    // -- 3. 무선 신호 아크 (배경, 연한 퍼플) --
    let cx = size * 0.50
    let cy = size * 0.44
    let arcRadii: [(r: CGFloat, alpha: CGFloat)] = [
        (size * 0.42, 0.14),
        (size * 0.30, 0.22),
        (size * 0.18, 0.30),
    ]
    ctx.setLineCap(.round)
    for arc in arcRadii {
        ctx.setStrokeColor(cgColor(160, 120, 255, arc.alpha))
        ctx.setLineWidth(size * 0.028)
        // 위쪽 반원 아크
        ctx.addArc(center: CGPoint(x: cx, y: cy),
                   radius: arc.r,
                   startAngle: .pi * 0.15,
                   endAngle: .pi * 0.85,
                   clockwise: true)
        ctx.strokePath()
    }

    // -- 4. Mac 화면 (흰색 라운드 사각형) --
    let screenW = size * 0.55
    let screenH = size * 0.38
    let screenX = cx - screenW / 2
    let screenY = cy - screenH / 2 - size * 0.03
    let screenR = size * 0.055

    // 화면 그림자
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.06,
                  color: cgColor(0, 0, 0, 0.55))

    // 화면 본체: 흰색 (살짝 파란 흰색)
    let screenPath = CGPath(roundedRect: CGRect(x: screenX, y: screenY, width: screenW, height: screenH),
                            cornerWidth: screenR, cornerHeight: screenR, transform: nil)
    ctx.addPath(screenPath)
    ctx.setFillColor(cgColor(235, 238, 255))
    ctx.fillPath()

    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // 화면 내부 앱 그리드 (3×2 컬러 도트)
    let dotCount = (cols: 3, rows: 2)
    let dotSize = size * 0.075
    let dotSpacingX = size * 0.125
    let dotSpacingY = size * 0.11
    let gridW = CGFloat(dotCount.cols - 1) * dotSpacingX
    let gridH = CGFloat(dotCount.rows - 1) * dotSpacingY
    let gridX = cx - gridW / 2
    let gridY = screenY + (screenH - gridH) / 2 - size * 0.012
    let dotCorner = dotSize * 0.28

    let dotColors: [[CGFloat]] = [
        [255, 80, 100],    // 빨강
        [255, 180, 40],    // 주황
        [60, 200, 120],    // 초록
        [80, 160, 255],    // 파랑
        [180, 100, 255],   // 보라
        [255, 120, 200],   // 핑크
    ]
    var colorIdx = 0
    for row in 0..<dotCount.rows {
        for col in 0..<dotCount.cols {
            let dx = gridX + CGFloat(col) * dotSpacingX - dotSize / 2
            let dy = gridY + CGFloat(row) * dotSpacingY - dotSize / 2
            let dc = dotColors[colorIdx % dotColors.count]
            let dotPath = CGPath(roundedRect: CGRect(x: dx, y: dy, width: dotSize, height: dotSize),
                                 cornerWidth: dotCorner, cornerHeight: dotCorner, transform: nil)
            ctx.addPath(dotPath)
            ctx.setFillColor(cgColor(dc[0], dc[1], dc[2]))
            ctx.fillPath()
            colorIdx += 1
        }
    }

    // 화면 베젤 하단 스탠드
    let standW = size * 0.08
    let standH = size * 0.07
    let standX = cx - standW / 2
    let standY = screenY - standH
    ctx.setFillColor(cgColor(200, 205, 240, 0.85))
    ctx.fill(CGRect(x: standX, y: standY, width: standW, height: standH))
    // 받침대
    let baseW = size * 0.20
    let baseH = size * 0.025
    ctx.setFillColor(cgColor(190, 195, 235, 0.80))
    let baseX = cx - baseW / 2
    let baseY = standY - baseH + size * 0.01
    let basePath = CGPath(roundedRect: CGRect(x: baseX, y: baseY, width: baseW, height: baseH),
                          cornerWidth: baseH / 2, cornerHeight: baseH / 2, transform: nil)
    ctx.addPath(basePath)
    ctx.fillPath()

    // -- 5. 핵심 무선 신호 아크 (선명한 흰색) --
    let sigRadii: [(r: CGFloat, alpha: CGFloat)] = [
        (size * 0.18, 0.95),
        (size * 0.30, 0.65),
        (size * 0.42, 0.35),
    ]
    for sig in sigRadii {
        ctx.setStrokeColor(cgColor(255, 255, 255, sig.alpha))
        ctx.setLineWidth(size * 0.030)
        ctx.addArc(center: CGPoint(x: cx, y: cy),
                   radius: sig.r,
                   startAngle: .pi * 0.18,
                   endAngle: .pi * 0.82,
                   clockwise: true)
        ctx.strokePath()
    }

    // -- 6. 중앙 신호 원점 --
    let dotR = size * 0.035
    ctx.addEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))
    ctx.setFillColor(cgColor(255, 255, 255))
    ctx.fillPath()

    image.unlockFocus()
    return image
}

// MARK: - Save PNG

func savePNG(_ image: NSImage, to path: String, size: CGFloat) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(size), pixelsHigh: Int(size),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    let url = URL(fileURLWithPath: path)
    try? data.write(to: url)
    print("✅ \(path) (\(Int(size))px)")
}

// MARK: - Main

let projectRoot = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

let macIconDir = "\(projectRoot)/MacApp/Resources/Assets.xcassets/AppIcon.appiconset"
let iosIconDir = "\(projectRoot)/iOSApp/Resources/Assets.xcassets/AppIcon.appiconset"

// macOS 아이콘 (10가지 사이즈)
let macSizes: [(filename: String, px: CGFloat)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png",256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png",512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png",1024),
]

print("🎨 Generating macOS icons…")
for (filename, px) in macSizes {
    let icon = drawIcon(size: px, forMac: true)
    savePNG(icon, to: "\(macIconDir)/\(filename)", size: px)
}

// iOS 아이콘 (1024px)
print("\n🎨 Generating iOS icon…")
let iosIcon = drawIcon(size: 1024, forMac: false)
savePNG(iosIcon, to: "\(iosIconDir)/icon_1024.png", size: 1024)

print("\n✨ Done.")
