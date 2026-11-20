#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Generates the Chronos-family minimal flat geometric AppIcon set for Tekmor.
// Usage: swift Distribution/generate_icon.swift

struct IconSpec {
  let filename: String
  let pixels: Int
}

let specs: [IconSpec] = [
  IconSpec(filename: "Icon-16@1x.png", pixels: 16),
  IconSpec(filename: "Icon-16@2x.png", pixels: 32),
  IconSpec(filename: "Icon-32@1x.png", pixels: 32),
  IconSpec(filename: "Icon-32@2x.png", pixels: 64),
  IconSpec(filename: "Icon-128@1x.png", pixels: 128),
  IconSpec(filename: "Icon-128@2x.png", pixels: 256),
  IconSpec(filename: "Icon-256@1x.png", pixels: 256),
  IconSpec(filename: "Icon-256@2x.png", pixels: 512),
  IconSpec(filename: "Icon-512@1x.png", pixels: 512),
  IconSpec(filename: "Icon-512@2x.png", pixels: 1024),
]

func srgb(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
  let r = CGFloat((hex >> 16) & 0xFF) / 255.0
  let g = CGFloat((hex >> 8) & 0xFF) / 255.0
  let b = CGFloat(hex & 0xFF) / 255.0
  return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, alpha])!
}

/// Draws an Apple HIG-proportioned macOS icon squircle inside `rect`.
func squirclePath(in rect: CGRect, radius: CGFloat) -> CGPath {
  // True continuous rounded-square silhouette matching macOS Dock icons
  let path = CGMutablePath()
  let minX = rect.minX
  let maxX = rect.maxX
  let minY = rect.minY
  let maxY = rect.maxY
  let r = min(radius, min(rect.width, rect.height) * 0.42)
  let k: CGFloat = r * 1.08
  let c: CGFloat = r * 0.44

  path.move(to: CGPoint(x: minX + k, y: maxY))
  path.addLine(to: CGPoint(x: maxX - k, y: maxY))
  path.addCurve(
    to: CGPoint(x: maxX, y: maxY - k),
    control1: CGPoint(x: maxX - c, y: maxY),
    control2: CGPoint(x: maxX, y: maxY - c))
  path.addLine(to: CGPoint(x: maxX, y: minY + k))
  path.addCurve(
    to: CGPoint(x: maxX - k, y: minY),
    control1: CGPoint(x: maxX, y: minY + c),
    control2: CGPoint(x: maxX - c, y: minY))
  path.addLine(to: CGPoint(x: minX + k, y: minY))
  path.addCurve(
    to: CGPoint(x: minX, y: minY + k),
    control1: CGPoint(x: minX + c, y: minY),
    control2: CGPoint(x: minX, y: minY + c))
  path.addLine(to: CGPoint(x: minX, y: maxY - k))
  path.addCurve(
    to: CGPoint(x: minX + k, y: maxY),
    control1: CGPoint(x: minX, y: maxY - c),
    control2: CGPoint(x: minX + c, y: maxY))
  path.closeSubpath()
  return path
}

/// Maps normalized design coordinates (0...108, top-left origin like SVG) into the icon tile rect (CoreGraphics bottom-left origin).
func point(_ x: CGFloat, _ y: CGFloat, in tile: CGRect) -> CGPoint {
  CGPoint(
    x: tile.minX + (x / 108.0) * tile.width,
    y: tile.maxY - (y / 108.0) * tile.height
  )
}

func renderIcon(pixels: Int) -> CGImage {
  let size = CGFloat(pixels)
  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  let context = CGContext(
    data: nil,
    width: pixels,
    height: pixels,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!

  context.setAllowsAntialiasing(true)
  context.setShouldAntialias(true)
  context.interpolationQuality = .high

  // macOS HIG icon canvas: ~824x824 tile centered inside 1024x1024 (100/1024 inset)
  let inset = size * (100.0 / 1024.0)
  let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
  let cornerRadius = tile.width * 0.225
  let squircle = squirclePath(in: tile, radius: cornerRadius)

  // 1. Soft macOS Dock drop shadow behind the white squircle tile
  context.saveGState()
  context.setShadow(
    offset: CGSize(width: 0, height: -size * 0.018),
    blur: size * 0.042,
    color: srgb(0x0B1F33, alpha: 0.20)
  )
  context.addPath(squircle)
  context.setFillColor(srgb(0xFFFFFF))
  context.fillPath()
  context.restoreGState()

  // 2. Crisp pure-white to whisper-cool-blue tile fill (Chronos sibling canvas)
  context.saveGState()
  context.addPath(squircle)
  context.clip()
  let backgroundGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [srgb(0xFFFFFF), srgb(0xF3F7FC)] as CFArray,
    locations: [0.0, 1.0]
  )!
  context.drawLinearGradient(
    backgroundGradient,
    start: CGPoint(x: tile.midX, y: tile.maxY),
    end: CGPoint(x: tile.midX, y: tile.minY),
    options: []
  )
  context.restoreGState()

  // Subtle crisp rim border for separation against light wallpapers & light Finder windows
  context.saveGState()
  context.addPath(squircle)
  context.setStrokeColor(srgb(0xCBD7E6, alpha: 0.72))
  context.setLineWidth(max(0.75, size * 0.0028))
  context.strokePath()
  context.restoreGState()

  // Scale helper for 108-unit Chronos design grid inside the tile
  let u = tile.width / 108.0

  // Palette directly from Chronos icon & brand system
  let azure = srgb(0x087FE0)
  let deepBlue = srgb(0x0068B7)
  let cyan = srgb(0x08B9AE)
  let amber = srgb(0xE6AD45)
  let softPinBlue = srgb(0x7AB5EE)
  let softPinCyan = srgb(0x52C9C0)
  let softPinAmber = srgb(0xEFC879)

  // 3. Minimal geometric chip pins (2 crisp rounded ticks per side, color-harmonized with adjacent ribbon)
  context.saveGState()
  context.setLineCap(.round)
  context.setLineWidth(5.4 * u)

  let pinOffsets: [CGFloat] = [42.0, 66.0]
  let pinOuter: CGFloat = 15.5
  let pinInner: CGFloat = 23.0

  // Top pins (Azure)
  context.setStrokeColor(softPinBlue)
  for x in pinOffsets {
    context.move(to: point(x, pinOuter, in: tile))
    context.addLine(to: point(x, pinInner, in: tile))
  }
  context.strokePath()

  // Right pins (top Azure, bottom Amber)
  context.setStrokeColor(softPinBlue)
  context.move(to: point(108 - pinOuter, pinOffsets[0], in: tile))
  context.addLine(to: point(108 - pinInner, pinOffsets[0], in: tile))
  context.strokePath()

  context.setStrokeColor(softPinAmber)
  context.move(to: point(108 - pinOuter, pinOffsets[1], in: tile))
  context.addLine(to: point(108 - pinInner, pinOffsets[1], in: tile))
  context.strokePath()

  // Left pins (top Azure, bottom Cyan)
  context.setStrokeColor(softPinBlue)
  context.move(to: point(pinOuter, pinOffsets[0], in: tile))
  context.addLine(to: point(pinInner, pinOffsets[0], in: tile))
  context.strokePath()

  context.setStrokeColor(softPinCyan)
  context.move(to: point(pinOuter, pinOffsets[1], in: tile))
  context.addLine(to: point(pinInner, pinOffsets[1], in: tile))
  context.strokePath()

  // Bottom pins (left Cyan, right Amber)
  context.setStrokeColor(softPinCyan)
  context.move(to: point(pinOffsets[0], 108 - pinOuter, in: tile))
  context.addLine(to: point(pinOffsets[0], 108 - pinInner, in: tile))
  context.strokePath()

  context.setStrokeColor(softPinAmber)
  context.move(to: point(pinOffsets[1], 108 - pinOuter, in: tile))
  context.addLine(to: point(pinOffsets[1], 108 - pinInner, in: tile))
  context.strokePath()
  context.restoreGState()

  // 4. Outer Chip Ribbon Frame (Chronos-style bold round-capped overlapping ribbons!)
  let ribbonWidth = 11.4 * u
  let minC: CGFloat = 28.0
  let maxC: CGFloat = 80.0
  let cr: CGFloat = 14.0

  // Upper-left -> Top -> Upper-right -> Right-mid (Chronos Azure #087FE0)
  func upperRibbonPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: point(minC, 54.0, in: tile))
    p.addLine(to: point(minC, minC + cr, in: tile))
    p.addArc(
      tangent1End: point(minC, minC, in: tile),
      tangent2End: point(minC + cr, minC, in: tile),
      radius: cr * u)
    p.addLine(to: point(maxC - cr, minC, in: tile))
    p.addArc(
      tangent1End: point(maxC, minC, in: tile),
      tangent2End: point(maxC, minC + cr, in: tile),
      radius: cr * u)
    p.addLine(to: point(maxC, 45.0, in: tile))
    return p
  }

  // Left-mid -> Bottom-left -> Bottom -> stops cleanly under Amber overlap
  func lowerRibbonPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: point(minC, 54.0, in: tile))
    p.addLine(to: point(minC, maxC - cr, in: tile))
    p.addArc(
      tangent1End: point(minC, maxC, in: tile),
      tangent2End: point(minC + cr, maxC, in: tile),
      radius: cr * u)
    p.addLine(to: point(66.5, maxC, in: tile))
    return p
  }

  // Bottom-right Warm Amber accent corner (exact Chronos #E6AD45 lower-right ribbon!)
  func amberAccentPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: point(65.0, maxC, in: tile))
    p.addLine(to: point(maxC - cr, maxC, in: tile))
    p.addArc(
      tangent1End: point(maxC, maxC, in: tile),
      tangent2End: point(maxC, maxC - cr, in: tile),
      radius: cr * u)
    p.addLine(to: point(maxC, 63.0, in: tile))
    return p
  }

  // Draw Upper Ribbon (solid Chronos Azure)
  context.saveGState()
  context.addPath(upperRibbonPath())
  context.setStrokeColor(azure)
  context.setLineWidth(ribbonWidth)
  context.setLineCap(.round)
  context.setLineJoin(.round)
  context.strokePath()
  context.restoreGState()

  // Draw Lower Ribbon with Cyan -> Azure linear gradient
  context.saveGState()
  let strokedLower = lowerRibbonPath().copy(
    strokingWithWidth: ribbonWidth,
    lineCap: .round,
    lineJoin: .round,
    miterLimit: 10
  )
  context.addPath(strokedLower)
  context.clip()
  let lowerGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [cyan, azure] as CFArray,
    locations: [0.0, 1.0]
  )!
  context.drawLinearGradient(
    lowerGradient,
    start: point(minC, 56.0, in: tile),
    end: point(66.0, maxC, in: tile),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
  )
  context.restoreGState()

  // Draw Amber Accent Ribbon overlapping the lower-right corner cleanly (zero blue bleed)
  context.saveGState()
  context.addPath(amberAccentPath())
  context.setStrokeColor(amber)
  context.setLineWidth(ribbonWidth)
  context.setLineCap(.round)
  context.setLineJoin(.round)
  context.strokePath()
  context.restoreGState()

  // 5. Inner Core Mark: Crisp Digital Signal Pulse Wave (Chronos #0068B7 -> #087FE0)
  context.saveGState()
  let pulse = CGMutablePath()
  pulse.move(to: point(39.5, 55.0, in: tile))
  pulse.addLine(to: point(45.8, 55.0, in: tile))
  pulse.addLine(to: point(51.0, 43.0, in: tile))
  pulse.addLine(to: point(57.2, 65.0, in: tile))
  pulse.addLine(to: point(62.2, 55.0, in: tile))
  pulse.addLine(to: point(68.5, 55.0, in: tile))

  let strokedPulse = pulse.copy(
    strokingWithWidth: 5.5 * u,
    lineCap: .round,
    lineJoin: .round,
    miterLimit: 10
  )
  context.addPath(strokedPulse)
  context.clip()
  let pulseGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [deepBlue, azure] as CFArray,
    locations: [0.0, 1.0]
  )!
  context.drawLinearGradient(
    pulseGradient,
    start: point(39.5, 55.0, in: tile),
    end: point(68.5, 55.0, in: tile),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
  )
  context.restoreGState()

  return context.makeImage()!
}

func savePNG(_ image: CGImage, to url: URL) throws {
  let rep = NSBitmapImageRep(cgImage: image)
  rep.size = NSSize(width: image.width, height: image.height)
  guard let data = rep.representation(using: .png, properties: [:]) else {
    throw NSError(
      domain: "TekmorIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
  }
  try data.write(to: url, options: .atomic)
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let iconsetDir = repoRoot.appendingPathComponent(
  "Tekmor/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

for spec in specs {
  let image = renderIcon(pixels: spec.pixels)
  let destination = iconsetDir.appendingPathComponent(spec.filename)
  try savePNG(image, to: destination)
  print("Wrote \(spec.filename) (\(spec.pixels)x\(spec.pixels))")
}
