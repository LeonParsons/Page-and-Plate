#!/usr/bin/env swift
//
// Renders the three 1024 app-icon PNGs from the same geometry as `BrandMark`.
//
//   swift ios/Tools/RenderAppIcon.swift
//
// Writes into ios/RecipeBasket/Assets.xcassets/AppIcon.appiconset/. Committed this time: the script that drew
// the first icon was never checked in, so re-rendering it meant rewriting it from scratch (docs/DECISIONS.md).

import AppKit
import CoreGraphics
import Foundation

struct Variant {
    let name: String
    let background: CGColor
    let ink: CGColor
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

let variants = [
    Variant(name: "AppIcon", background: rgb(0xB23A1B), ink: rgb(0xFAF7F0)),
    Variant(name: "AppIcon-Dark", background: rgb(0x1A1713), ink: rgb(0xF2775A)),
    Variant(name: "AppIcon-Tinted", background: rgb(0xD8D8D8), ink: rgb(0x2A2A2A)),
]

let side = 1024

// The mark is drawn in the same 100 x 100 space as `BrandMark`, but inset: drawn edge to edge the rim crowds
// the corners once iOS applies its rounded mask, and the strokes read far heavier than they do in the app.
let markFraction: CGFloat = 0.78
let markSide = CGFloat(side) * markFraction
let inset = (CGFloat(side) - markSide) / 2
let scale = markSide / 100

/// The open book, both leaves. `direction` mirrors the left leaf onto the right.
func pagesPath() -> CGPath {
    let path = CGMutablePath()
    for direction in [CGFloat(-1), 1] {
        func x(_ offset: CGFloat) -> CGFloat { 50 + offset * direction }
        path.move(to: CGPoint(x: 50, y: 41))
        path.addCurve(
            to: CGPoint(x: x(25), y: 36.5),
            control1: CGPoint(x: x(7), y: 36),
            control2: CGPoint(x: x(17), y: 35)
        )
        path.addLine(to: CGPoint(x: x(25), y: 61))
        path.addCurve(
            to: CGPoint(x: 50, y: 65),
            control1: CGPoint(x: x(17), y: 59.5),
            control2: CGPoint(x: x(7), y: 60.5)
        )
    }
    return path
}

for variant in variants {
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue   // App Store icons must carry no alpha
    ) else {
        fatalError("could not make a context for \(variant.name)")
    }

    context.setFillColor(variant.background)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))

    // Flip so the 100 x 100 coordinates read top-down, as they do in the SwiftUI Canvas and the SVG.
    context.translateBy(x: 0, y: CGFloat(side))
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: inset, y: inset)
    context.scaleBy(x: scale, y: scale)

    context.setStrokeColor(variant.ink)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    context.setLineWidth(4)
    context.strokeEllipse(in: CGRect(x: 8, y: 8, width: 84, height: 84))

    context.saveGState()
    context.setAlpha(0.4)
    context.setLineWidth(2)
    context.strokeEllipse(in: CGRect(x: 19, y: 19, width: 62, height: 62))
    context.restoreGState()

    context.setLineWidth(4.5)
    context.addPath(pagesPath())
    context.strokePath()

    context.setLineWidth(3)
    context.move(to: CGPoint(x: 50, y: 41))
    context.addLine(to: CGPoint(x: 50, y: 65))
    context.strokePath()

    guard let image = context.makeImage() else { fatalError("no image for \(variant.name)") }
    let url = URL(fileURLWithPath: "ios/RecipeBasket/Assets.xcassets/AppIcon.appiconset/\(variant.name).png")
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("no PNG data for \(variant.name)")
    }
    try data.write(to: url)
    print("wrote \(url.lastPathComponent)")
}
