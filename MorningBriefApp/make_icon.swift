// Generates icon_1024.png — the master app icon.
// Run: swift make_icon.swift   (then: see build_icon.sh / README)
import AppKit

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// macOS-style rounded square with margin (Big Sur geometry: 824pt, r=185)
let squircle = NSBezierPath(
    roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
    xRadius: 185, yRadius: 185)

// dawn sky gradient: deep night blue up top, warm sunrise at the horizon
NSGradient(colors: [
    NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.30, alpha: 1),
    NSColor(calibratedRed: 0.93, green: 0.42, blue: 0.28, alpha: 1),
    NSColor(calibratedRed: 0.18, green: 0.16, blue: 0.38, alpha: 1),
])!.draw(in: squircle, angle: 90)

// sunrise symbol
let symbolConfig = NSImage.SymbolConfiguration(pointSize: 430, weight: .medium)
if let symbol = NSImage(systemSymbolName: "sunrise.fill",
                        accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    let r = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let s = symbol.size
    let scale = 560 / max(s.width, s.height)
    let w = s.width * scale, h = s.height * scale
    tinted.draw(in: NSRect(x: (canvas - w) / 2, y: (canvas - h) / 2 - 20,
                           width: w, height: h))
}

image.unlockFocus()

let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "icon_1024.png"))
print("wrote icon_1024.png")
