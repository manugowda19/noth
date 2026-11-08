import AppKit

// Renders NotchFlow's app icon: a black hardware-notch glyph on a bright
// indigo squircle, so it stays legible down to 16px in the Dock/menu bar.
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Squircle mask (macOS icons must carry their own rounded-corner shape).
let corner = size * 0.225
let full = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                         xRadius: corner, yRadius: corner)
full.addClip()

// Background: bright indigo -> violet, top to bottom.
let bg = NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.36, blue: 0.95, alpha: 1),
                     ending: NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.90, alpha: 1))!
bg.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

// The notch: a black pill hanging from the top edge, rounded on the bottom
// corners only — same shape ShelfView draws on-screen, sized to read clearly
// at small icon sizes.
let notchWidth = size * 0.56
let notchHeight = size * 0.34
let notchRect = NSRect(x: (size - notchWidth) / 2, y: size - notchHeight,
                        width: notchWidth, height: notchHeight)
let r = notchHeight * 0.42
let notchPath = NSBezierPath()
notchPath.move(to: NSPoint(x: notchRect.minX, y: notchRect.maxY))
notchPath.line(to: NSPoint(x: notchRect.minX, y: notchRect.minY + r))
notchPath.appendArc(withCenter: NSPoint(x: notchRect.minX + r, y: notchRect.minY + r),
                     radius: r, startAngle: 180, endAngle: 270, clockwise: false)
notchPath.line(to: NSPoint(x: notchRect.maxX - r, y: notchRect.minY))
notchPath.appendArc(withCenter: NSPoint(x: notchRect.maxX - r, y: notchRect.minY + r),
                     radius: r, startAngle: 270, endAngle: 360, clockwise: false)
notchPath.line(to: NSPoint(x: notchRect.maxX, y: notchRect.maxY))
notchPath.close()
NSColor.black.setFill()
notchPath.fill()

// A single parked "file chip" dot inside the notch, bright enough to read
// against the black at small sizes.
let dotSize = size * 0.12
let dot = NSBezierPath(ovalIn: NSRect(x: size/2 - dotSize/2,
                                      y: size - notchHeight * 0.60 - dotSize/2,
                                      width: dotSize, height: dotSize))
NSColor(calibratedRed: 0.36, green: 0.36, blue: 0.95, alpha: 1).setFill()
dot.fill()

ctx.flush()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render icon")
}
let outPath = CommandLine.arguments[1]
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
