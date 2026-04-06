#!/usr/bin/env swift
// Generates a branded DMG background image for Runway.
// Usage: swift scripts/generate-dmg-background.swift <output-path>
//
// Produces a 600x400 @2x PNG (1200x800 pixels) with:
// - Dark gradient background
// - "Runway" title text
// - Drag arrow indicator

import Cocoa

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate-dmg-background <output.png>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let width = 1200  // 600pt @2x
let height = 800  // 400pt @2x

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
          data: nil,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else {
    fputs("Error: Failed to create graphics context\n", stderr)
    exit(1)
}

// Dark gradient background
let gradientColors = [
    CGColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1.0),
    CGColor(red: 0.16, green: 0.16, blue: 0.22, alpha: 1.0),
]
if let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradientColors as CFArray,
    locations: [0.0, 1.0]
) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(height)),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
}

// "Runway" title — centered, upper third
let titleFont = NSFont.systemFont(ofSize: 72, weight: .bold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor(white: 1.0, alpha: 0.9),
]
let titleStr = NSAttributedString(string: "Runway", attributes: titleAttrs)
let titleLine = CTLineCreateWithAttributedString(titleStr)
let titleBounds = CTLineGetBoundsWithOptions(titleLine, .useOpticalBounds)
let titleX = (CGFloat(width) - titleBounds.width) / 2
let titleY = CGFloat(height) * 0.65

ctx.saveGState()
ctx.textPosition = CGPoint(x: titleX, y: titleY)
CTLineDraw(titleLine, ctx)
ctx.restoreGState()

// Arrow: simple "drag to install" indicator between icon positions
// The app icon sits at ~170pt (340px) and Applications at ~430pt (860px)
let arrowY = CGFloat(height) * 0.38
let arrowLeft: CGFloat = 440
let arrowRight: CGFloat = 760
let arrowColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.35)

ctx.setStrokeColor(arrowColor)
ctx.setLineWidth(4.0)
ctx.setLineCap(.round)

// Shaft
ctx.move(to: CGPoint(x: arrowLeft, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowRight, y: arrowY))
ctx.strokePath()

// Arrowhead
let headSize: CGFloat = 24
ctx.move(to: CGPoint(x: arrowRight - headSize, y: arrowY + headSize))
ctx.addLine(to: CGPoint(x: arrowRight, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowRight - headSize, y: arrowY - headSize))
ctx.strokePath()

// Subtitle
let subFont = NSFont.systemFont(ofSize: 28, weight: .medium)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: NSColor(white: 1.0, alpha: 0.4),
]
let subStr = NSAttributedString(string: "Drag to Applications to install", attributes: subAttrs)
let subLine = CTLineCreateWithAttributedString(subStr)
let subBounds = CTLineGetBoundsWithOptions(subLine, .useOpticalBounds)
let subX = (CGFloat(width) - subBounds.width) / 2
let subY = CGFloat(height) * 0.18

ctx.saveGState()
ctx.textPosition = CGPoint(x: subX, y: subY)
CTLineDraw(subLine, ctx)
ctx.restoreGState()

// Write PNG
guard let image = ctx.makeImage() else {
    fputs("Error: Failed to create image\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("Error: Failed to create image destination\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("Error: Failed to write PNG\n", stderr)
    exit(1)
}

print("Generated DMG background: \(outputPath) (\(width)x\(height))")
