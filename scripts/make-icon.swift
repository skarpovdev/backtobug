import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let unit = CGFloat(pixels) / 1_024
    let transform = NSAffineTransform()
    transform.scale(by: unit)
    transform.concat()
    let rect = NSRect(x: 70, y: 70, width: 884, height: 884)
    let background = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
    NSGradient(
      starting: NSColor(srgbRed: 0.28, green: 0.44, blue: 1, alpha: 1),
      ending: NSColor(srgbRed: 0.13, green: 0.25, blue: 0.79, alpha: 1))!.draw(
        in: background, angle: -70)
    let config = NSImage.SymbolConfiguration(pointSize: 480, weight: .semibold)
    let symbol = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)!
      .withSymbolConfiguration(config)!
    let white = NSImage(size: symbol.size)
    white.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: symbol.size).fill()
    symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
    white.unlockFocus()
    white.draw(in: NSRect(x: 267, y: 230, width: 490, height: 550))
    NSColor(srgbRed: 0.40, green: 0.96, blue: 0.70, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 742, y: 710, width: 104, height: 104)).fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let suffix = scale == 2 ? "@2x" : ""
    let url = URL(fileURLWithPath: destination).appendingPathComponent(
      "icon_\(size)x\(size)\(suffix).png")
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
  }
}
