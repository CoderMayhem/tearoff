#!/usr/bin/env swift
// Renders Tearoff's app icon into an .iconset directory.
import AppKit
import Foundation

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

func draw(size s: CGFloat) -> NSBitmapImageRep {
    let px = Int(s)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded-square backdrop, warm charcoal.
    let inset = s * 0.06
    let plate = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let plateRadius = plate.width * 0.2237
    let platePath = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)
    NSGradient(starting: color(0x3D342B), ending: color(0x1F1B17))!
        .draw(in: platePath, angle: -90)

    // The pad.
    let padW = s * 0.54
    let padH = s * 0.60
    let padX = (s - padW) / 2
    let padY = s * 0.20
    let padRadius = padW * 0.09
    let pad = NSRect(x: padX, y: padY, width: padW, height: padH)

    NSGraphicsContext.current?.cgContext.setShadow(
        offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035,
        color: NSColor.black.withAlphaComponent(0.45).cgColor)

    let sheetPath = NSBezierPath(roundedRect: pad, xRadius: padRadius, yRadius: padRadius)
    color(0xF8F1E3).setFill()
    sheetPath.fill()
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    // Header board, clipped to the pad's top corners.
    NSGraphicsContext.saveGraphicsState()
    sheetPath.setClip()
    let headerH = padH * 0.26
    color(0xC0562B).setFill()
    NSBezierPath(rect: NSRect(x: padX, y: pad.maxY - headerH, width: padW, height: headerH)).fill()

    // Punch holes.
    color(0x2A1A12).setFill()
    let holeR = padW * 0.045
    for dx in [-padW * 0.18, padW * 0.18] {
        let c = NSPoint(x: pad.midX + dx, y: pad.maxY - headerH * 0.45)
        NSBezierPath(ovalIn: NSRect(x: c.x - holeR, y: c.y - holeR, width: holeR * 2, height: holeR * 2)).fill()
    }

    // Torn edge just below the binding.
    let torn = NSBezierPath()
    let tearY = pad.maxY - headerH - padH * 0.035
    torn.move(to: NSPoint(x: padX, y: tearY))
    var x = padX
    var up = true
    let step = padW / 11
    while x < pad.maxX {
        x = min(x + step, pad.maxX)
        torn.line(to: NSPoint(x: x, y: tearY + (up ? padH * 0.022 : 0)))
        up.toggle()
    }
    torn.line(to: NSPoint(x: pad.maxX, y: tearY - padH * 0.02))
    torn.line(to: NSPoint(x: padX, y: tearY - padH * 0.02))
    torn.close()
    color(0xE3D7C1).setFill()
    torn.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The numeral.
    let fontSize = padH * 0.44
    let font = NSFont(descriptor: NSFont.systemFont(ofSize: fontSize)
        .fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: fontSize).fontDescriptor,
                      size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
    let text = NSAttributedString(string: "21", attributes: [
        .font: font,
        .foregroundColor: color(0x2A2622),
    ])
    let textSize = text.size()
    text.draw(at: NSPoint(x: pad.midX - textSize.width / 2,
                          y: padY + (padH - headerH) * 0.34 - textSize.height * 0.12))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

let specs: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (pt, scale) in specs {
    let rep = draw(size: CGFloat(pt * scale))
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    try! data.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
}
print("iconset written to \(out)")
