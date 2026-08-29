#!/usr/bin/env swift

import AppKit

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let screenshots = root.appendingPathComponent("docs/screenshots")

private enum Palette {
    static let blue = NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)
    static let ink = NSColor(calibratedWhite: 0.98, alpha: 1)
    static let muted = NSColor(calibratedRed: 0.67, green: 0.73, blue: 0.82, alpha: 1)
    static let line = NSColor(calibratedWhite: 1, alpha: 0.14)
}

private func image(_ relativePath: String) -> NSImage {
    let url = root.appendingPathComponent(relativePath)
    guard let value = NSImage(contentsOf: url) else {
        fatalError("Could not load \(url.path)")
    }
    return value
}

private func withCanvas(size: NSSize, draw: () -> Void) -> NSImage {
    let canvas = NSImage(size: size)
    canvas.lockFocusFlipped(true)
    NSColor.black.setFill()
    NSRect(origin: .zero, size: size).fill()
    draw()
    canvas.unlockFocus()
    return canvas
}

private func save(_ value: NSImage, name: String) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(value.size.width),
        pixelsHigh: Int(value.size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not rasterize \(name)")
    }
    rep.size = value.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    value.draw(in: NSRect(origin: .zero, size: value.size), from: NSRect(origin: .zero, size: value.size), operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [.compressionFactor: 0.9]) else {
        fatalError("Could not encode \(name)")
    }
    let url = screenshots.appendingPathComponent(name)
    try! png.write(to: url, options: .atomic)
    print("Rendered \(url.path)")
}

private func cover(_ value: NSImage, in rect: NSRect, fraction: CGFloat = 1) {
    let sourceRatio = value.size.width / value.size.height
    let targetRatio = rect.width / rect.height
    var source = NSRect(origin: .zero, size: value.size)
    if sourceRatio > targetRatio {
        let width = value.size.height * targetRatio
        source.origin.x = (value.size.width - width) / 2
        source.size.width = width
    } else {
        let height = value.size.width / targetRatio
        source.origin.y = (value.size.height - height) / 2
        source.size.height = height
    }
    value.draw(in: rect, from: source, operation: .sourceOver, fraction: fraction, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
}

private func roundedImage(_ value: NSImage, in rect: NSRect, radius: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    cover(value, in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

private func panel(_ rect: NSRect, radius: CGFloat = 28, fill: NSColor = NSColor(calibratedWhite: 0.03, alpha: 0.72), shadow: Bool = true) {
    NSGraphicsContext.saveGraphicsState()
    if shadow {
        let value = NSShadow()
        value.shadowColor = NSColor.black.withAlphaComponent(0.58)
        value.shadowBlurRadius = 52
        value.shadowOffset = NSSize(width: 0, height: 26)
        value.set()
    }
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()
    Palette.line.setStroke()
    let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
    outline.lineWidth = 1
    outline.stroke()
}

@discardableResult
private func text(
    _ string: String,
    in rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = Palette.ink,
    alignment: NSTextAlignment = .left,
    lineHeight: CGFloat? = nil,
    tracking: CGFloat = 0
) -> NSRect {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: tracking
    ]
    let value = NSAttributedString(string: string, attributes: attributes)
    value.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    return rect
}

private func eyebrow(_ string: String, at point: NSPoint) {
    Palette.blue.setFill()
    NSBezierPath(roundedRect: NSRect(x: point.x, y: point.y + 11, width: 31, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    text(string.uppercased(), in: NSRect(x: point.x + 45, y: point.y, width: 530, height: 28), size: 16, weight: .bold, color: NSColor(calibratedRed: 0.51, green: 0.73, blue: 1, alpha: 1), tracking: 1.8)
}

private func chip(_ label: String, x: CGFloat, y: CGFloat) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold)]
    let width = ceil((label as NSString).size(withAttributes: attributes).width) + 30
    let rect = NSRect(x: x, y: y, width: width, height: 38)
    NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.15, alpha: 0.75).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 19, yRadius: 19).fill()
    NSColor(calibratedRed: 0.55, green: 0.72, blue: 0.92, alpha: 0.35).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 19, yRadius: 19)
    border.lineWidth = 1
    border.stroke()
    text(label, in: NSRect(x: x, y: y + 9, width: width, height: 22), size: 15, weight: .semibold, color: NSColor(calibratedRed: 0.85, green: 0.91, blue: 0.98, alpha: 1), alignment: .center)
    return width
}

private let scanField = image("docs/screenshots/glint-scan-field.png")
private let icon = image("Sources/Glint/Resources/Brand/glint-app-icon-1024.png")
private let card = image("docs/screenshots/pinned-card-0.3.1.png")
private let scanning = image("docs/screenshots/settings-scanning-0.3.1.png")
private let appearance = image("docs/screenshots/settings-appearance-0.3.1.png")

private let hero = withCanvas(size: NSSize(width: 1600, height: 900)) {
    cover(scanField, in: NSRect(x: 0, y: 0, width: 1600, height: 900))
    NSGradient(colorsAndLocations:
        (NSColor(calibratedWhite: 0.01, alpha: 0.05), 0),
        (NSColor(calibratedWhite: 0.01, alpha: 0.78), 1)
    )!.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 900), angle: 0)

    roundedImage(icon, in: NSRect(x: 82, y: 72, width: 76, height: 76), radius: 18)
    text("GLINT", in: NSRect(x: 178, y: 89, width: 220, height: 42), size: 31, weight: .bold)
    eyebrow("Context at the speed of sight", at: NSPoint(x: 84, y: 227))
    text("Point at a ticket.\nKnow what matters.", in: NSRect(x: 80, y: 274, width: 690, height: 178), size: 67, weight: .bold, lineHeight: 70, tracking: -2.7)
    text("A private macOS menu-bar utility that turns nearby issue references into useful, navigable cards.", in: NSRect(x: 84, y: 478, width: 590, height: 112), size: 25, color: NSColor(calibratedRed: 0.75, green: 0.81, blue: 0.89, alpha: 1), lineHeight: 36)
    var chipX: CGFloat = 84
    for label in ["Local OCR", "Read-only", "No AI upload"] {
        chipX += chip(label, x: chipX, y: 631) + 12
    }

    let outer = NSRect(x: 798, y: 151, width: 760, height: 592)
    panel(outer, radius: 30)
    roundedImage(card, in: outer.insetBy(dx: 11, dy: 11), radius: 21)
}
save(hero, name: "hero-0.3.1.png")

private let workflow = withCanvas(size: NSSize(width: 1600, height: 920)) {
    NSGradient(colors: [NSColor(calibratedRed: 0.025, green: 0.045, blue: 0.08, alpha: 1), NSColor(calibratedRed: 0.055, green: 0.09, blue: 0.14, alpha: 1)])!.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 920), angle: -25)
    eyebrow("One gesture, full context", at: NSPoint(x: 76, y: 63))
    text("Scan. Resolve. Keep moving.", in: NSRect(x: 74, y: 106, width: 760, height: 66), size: 52, weight: .bold, tracking: -2)
    text("Invoke GLINT at the pointer. It ranks the best source and keeps alternatives one scroll away.", in: NSRect(x: 1000, y: 72, width: 510, height: 95), size: 20, color: Palette.muted, alignment: .right, lineHeight: 29)

    let stage = NSRect(x: 74, y: 202, width: 1452, height: 648)
    panel(stage, radius: 30, fill: NSColor(calibratedRed: 0.035, green: 0.06, blue: 0.10, alpha: 1))
    NSColor(calibratedWhite: 1, alpha: 0.045).setFill()
    NSRect(x: stage.minX, y: stage.minY, width: stage.width, height: 44).fill()
    for index in 0..<3 {
        NSColor(calibratedRed: 0.18, green: 0.24, blue: 0.33, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: stage.minX + 19 + CGFloat(index * 18), y: stage.minY + 17, width: 10, height: 10)).fill()
    }

    NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
    NSBezierPath(roundedRect: NSRect(x: 142, y: 322, width: 505, height: 21), xRadius: 7, yRadius: 7).fill()
    NSColor(calibratedWhite: 1, alpha: 0.055).setFill()
    NSBezierPath(roundedRect: NSRect(x: 142, y: 365, width: 386, height: 13), xRadius: 6, yRadius: 6).fill()
    NSBezierPath(roundedRect: NSRect(x: 142, y: 394, width: 305, height: 13), xRadius: 6, yRadius: 6).fill()
    let token = NSRect(x: 142, y: 446, width: 165, height: 52)
    NSColor(calibratedRed: 0.04, green: 0.52, blue: 1, alpha: 0.13).setFill()
    NSBezierPath(roundedRect: token, xRadius: 10, yRadius: 10).fill()
    NSColor(calibratedRed: 0.04, green: 0.52, blue: 1, alpha: 0.45).setStroke()
    NSBezierPath(roundedRect: token.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10).stroke()
    text("GLINT-42", in: NSRect(x: 158, y: 458, width: 140, height: 30), size: 23, weight: .bold, color: NSColor(calibratedRed: 0.45, green: 0.70, blue: 1, alpha: 1))
    Palette.blue.withAlphaComponent(0.92).setStroke()
    let ripple = NSBezierPath(ovalIn: NSRect(x: 108, y: 423, width: 120, height: 120))
    ripple.lineWidth = 3
    ripple.stroke()
    Palette.blue.withAlphaComponent(0.13).setStroke()
    let outerRipple = NSBezierPath(ovalIn: NSRect(x: 91, y: 406, width: 154, height: 154))
    outerRipple.lineWidth = 12
    outerRipple.stroke()

    text("The first hit leads.", in: NSRect(x: 141, y: 677, width: 340, height: 34), size: 25, weight: .bold)
    text("Rich context up front. Ranked alternatives stay visible before you scroll.", in: NSRect(x: 141, y: 718, width: 330, height: 90), size: 18, color: Palette.muted, lineHeight: 27)

    let result = NSRect(x: 669, y: 224, width: 780, height: 607)
    panel(result, radius: 24)
    roundedImage(card, in: result.insetBy(dx: 9, dy: 9), radius: 16)
}
save(workflow, name: "workflow-0.3.1.png")

private let settingsShot = withCanvas(size: NSSize(width: 1600, height: 1040)) {
    NSGradient(colors: [NSColor(calibratedRed: 0.02, green: 0.035, blue: 0.065, alpha: 1), NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.14, alpha: 1)])!.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 1040), angle: -35)
    eyebrow("Made to fit your flow", at: NSPoint(x: 74, y: 61))
    text("Powerful, without becoming fussy.", in: NSRect(x: 72, y: 103, width: 900, height: 70), size: 52, weight: .bold, tracking: -2)
    text("Choose exactly how GLINT activates and how much context its card shows. Every change applies immediately.", in: NSRect(x: 1030, y: 66, width: 490, height: 100), size: 20, color: Palette.muted, alignment: .right, lineHeight: 29)

    let left = NSRect(x: 72, y: 210, width: 710, height: 660)
    panel(left, radius: 25)
    roundedImage(scanning, in: left.insetBy(dx: 9, dy: 9), radius: 17)
    let right = NSRect(x: 818, y: 210, width: 710, height: 660)
    panel(right, radius: 25)
    roundedImage(appearance, in: right.insetBy(dx: 9, dy: 9), radius: 17)
    _ = chip("Any safe global shortcut", x: 102, y: 906)
    _ = chip("Live, local preview", x: 1316, y: 906)
}
save(settingsShot, name: "settings-showcase-0.3.1.png")

private let social = withCanvas(size: NSSize(width: 1280, height: 640)) {
    cover(scanField, in: NSRect(x: 0, y: 0, width: 1280, height: 640))
    NSGradient(colorsAndLocations:
        (NSColor(calibratedWhite: 0.01, alpha: 0.08), 0),
        (NSColor(calibratedWhite: 0.01, alpha: 0.86), 1)
    )!.draw(in: NSRect(x: 0, y: 0, width: 1280, height: 640), angle: 0)
    roundedImage(icon, in: NSRect(x: 58, y: 50, width: 65, height: 65), radius: 15)
    text("Ticket context,\nright where you point.", in: NSRect(x: 56, y: 164, width: 570, height: 150), size: 55, weight: .bold, lineHeight: 58, tracking: -2.2)
    text("Private, instant issue lookup for macOS.", in: NSRect(x: 60, y: 340, width: 500, height: 64), size: 22, color: NSColor(calibratedRed: 0.74, green: 0.81, blue: 0.90, alpha: 1))
    eyebrow("GLINT", at: NSPoint(x: 60, y: 474))
    let cardRect = NSRect(x: 650, y: 83, width: 590, height: 459)
    panel(cardRect, radius: 24)
    roundedImage(card, in: cardRect.insetBy(dx: 9, dy: 9), radius: 16)
}
save(social, name: "social-preview-0.3.1.png")
