import AppKit
let n = 1024
let cg = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// flip to top-left origin
cg.translateBy(x: 0, y: CGFloat(n)); cg.scaleBy(x: 1, y: -1)
func c(_ h: UInt32, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: CGFloat((h>>16)&255)/255, green: CGFloat((h>>8)&255)/255, blue: CGFloat(h&255)/255, alpha: a) }
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// background gradient
let bg = CGGradient(colorsSpace: space, colors: [c(0x3B8BFF), c(0x4F46E5)] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])
// soft light glow top-left
let glow = CGGradient(colorsSpace: space, colors: [c(0xFFFFFF, 0.22), c(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
cg.drawRadialGradient(glow, startCenter: CGPoint(x: 230, y: 180), startRadius: 0, endCenter: CGPoint(x: 230, y: 180), endRadius: 620, options: [])
// soft shadow under glyph
cg.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: c(0x1E1B4B, 0.35))
// radical sign
let p = CGMutablePath()
p.move(to: CGPoint(x: 205, y: 560))
p.addLine(to: CGPoint(x: 300, y: 515))
p.addLine(to: CGPoint(x: 425, y: 790))
p.addLine(to: CGPoint(x: 575, y: 255))
p.addLine(to: CGPoint(x: 830, y: 255))
cg.addPath(p)
cg.setStrokeColor(c(0xFFFFFF)); cg.setLineWidth(78); cg.setLineCap(.round); cg.setLineJoin(.round)
cg.strokePath()
// amber spark inside the root (a 4-point star)
let star = CGMutablePath()
let cx: CGFloat = 712, cy: CGFloat = 505, R: CGFloat = 118, r: CGFloat = 34
for i in 0..<8 {
    let a = CGFloat(i) * .pi / 4 - .pi / 2
    let rad = i % 2 == 0 ? R : r
    let pt = CGPoint(x: cx + cos(a) * rad, y: cy + sin(a) * rad)
    i == 0 ? star.move(to: pt) : star.addLine(to: pt)
}
star.closeSubpath()
cg.addPath(star); cg.setFillColor(c(0xFFC53D)); cg.fillPath()
let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
