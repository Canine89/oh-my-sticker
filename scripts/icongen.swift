import AppKit

// 앱 아이콘 — 스퀘어클 배경 위에 살짝 기울어진 스티커 한 장과 별.
// 실행: swift scripts/icongen.swift  → Resources/Assets.xcassets/AppIcon.appiconset/*.png

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
let cg = context.cgContext

// 스퀘어클 배경
let margin: CGFloat = 92
let plate = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let corner = plate.width * 0.2237
let squircle = CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil)

cg.saveGState()
cg.addPath(squircle)
cg.clip()
let background = [NSColor(srgbRed: 0.42, green: 0.36, blue: 0.95, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.85, green: 0.31, blue: 0.72, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: background, locations: [0, 1])!
cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
cg.restoreGState()

// 기울어진 흰 스티커
cg.saveGState()
cg.translateBy(x: size / 2, y: size / 2)
cg.rotate(by: -10 * .pi / 180)
cg.translateBy(x: -size / 2, y: -size / 2)

let card = CGRect(x: size / 2 - 268, y: size / 2 - 268, width: 536, height: 536)
let cardPath = NSBezierPath(roundedRect: card, xRadius: 96, yRadius: 96)

cg.setShadow(offset: CGSize(width: 0, height: -26), blur: 52,
             color: NSColor.black.withAlphaComponent(0.32).cgColor)
NSColor.white.setFill()
cardPath.fill()
cg.setShadow(offset: .zero, blur: 0, color: nil)

// 스티커 안의 별
let star = NSBezierPath()
let center = CGPoint(x: card.midX, y: card.midY)
for index in 0..<10 {
    let radius: CGFloat = index % 2 == 0 ? 186 : 78
    let angle = CGFloat(index) * .pi / 5 + .pi / 2
    let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    if index == 0 { star.move(to: point) } else { star.line(to: point) }
}
star.close()
NSColor(srgbRed: 0.99, green: 0.72, blue: 0.16, alpha: 1).setFill()
star.fill()
cg.restoreGState()

NSGraphicsContext.current = nil

// 필요한 크기로 내려 저장
let outDir = "Resources/Assets.xcassets/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let full = NSImage(size: NSSize(width: size, height: size))
full.addRepresentation(rep)

for side in [16, 32, 64, 128, 256, 512, 1024] {
    let target = NSImage(size: NSSize(width: side, height: side))
    target.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    full.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
              from: NSRect(origin: .zero, size: full.size),
              operation: .copy, fraction: 1)
    target.unlockFocus()

    guard let tiff = target.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(side).png"))
    print("wrote icon_\(side).png")
}
