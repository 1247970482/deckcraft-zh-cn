import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.94, green: 0.36, blue: 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 210, yRadius: 210).fill()
NSColor(calibratedWhite: 1, alpha: 0.97).setFill()
NSBezierPath(roundedRect: NSRect(x: 165, y: 355, width: 505, height: 470), xRadius: 80, yRadius: 80).fill()
let warm = NSColor(calibratedRed: 0.94, green: 0.36, blue: 0.12, alpha: 1)
warm.setStroke()
let strokes = NSBezierPath(); strokes.lineWidth = 28; strokes.lineCapStyle = .round
for (a,b) in [(NSPoint(x: 320,y: 610),NSPoint(x: 540,y: 610)), (NSPoint(x: 425,y: 710),NSPoint(x: 425,y: 470)), (NSPoint(x: 320,y: 510),NSPoint(x: 540,y: 510))] { strokes.move(to: a); strokes.line(to: b) }
strokes.stroke()
NSColor(calibratedRed: 0.13, green: 0.22, blue: 0.29, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 445, y: 165, width: 410, height: 400), xRadius: 75, yRadius: 75).fill()
NSColor.white.setStroke()
let glyph = NSBezierPath(); glyph.lineWidth = 25; glyph.lineCapStyle = .round
glyph.move(to: NSPoint(x: 550,y: 425)); glyph.line(to: NSPoint(x: 750,y: 425))
glyph.move(to: NSPoint(x: 650,y: 475)); glyph.line(to: NSPoint(x: 650,y: 425))
glyph.move(to: NSPoint(x: 595,y: 420)); glyph.curve(to: NSPoint(x: 745,y: 250), controlPoint1: NSPoint(x: 620,y: 335), controlPoint2: NSPoint(x: 680,y: 280))
glyph.move(to: NSPoint(x: 710,y: 420)); glyph.curve(to: NSPoint(x: 550,y: 250), controlPoint1: NSPoint(x: 690,y: 335), controlPoint2: NSPoint(x: 620,y: 280))
glyph.stroke()
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)
