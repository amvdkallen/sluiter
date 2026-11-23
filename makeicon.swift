// Tekent het app-icoon (1024×1024 PNG). Gebruik: swift makeicon.swift uit.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS-icoonraster: inhoud 824×824 met marge, afgeronde hoeken
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

// schaduw
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// verloop rood → oranje
NSGradient(starting: NSColor(red: 1.0, green: 0.55, blue: 0.25, alpha: 1),
           ending: NSColor(red: 0.90, green: 0.18, blue: 0.25, alpha: 1))!
    .draw(in: shape, angle: -90)

// wit kruis
let cross = NSBezierPath()
cross.lineWidth = 110
cross.lineCapStyle = .round
cross.move(to: NSPoint(x: 340, y: 340)); cross.line(to: NSPoint(x: 684, y: 684))
cross.move(to: NSPoint(x: 684, y: 340)); cross.line(to: NSPoint(x: 340, y: 684))
NSColor.white.setStroke()
cross.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
