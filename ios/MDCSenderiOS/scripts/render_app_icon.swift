import AppKit
import ImageIO
import UniformTypeIdentifiers

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let canvas = CGSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawLinearGradient(in rect: CGRect, colors: [NSColor], angle: CGFloat) {
    let gradient = NSGradient(colors: colors)!
    gradient.draw(in: rect, angle: angle)
}

func drawPaperPlane(in rect: CGRect) {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.minY + rect.height * 0.57))
    path.line(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.10))
    path.line(to: CGPoint(x: rect.maxX - rect.width * 0.34, y: rect.minY + rect.height * 0.14))
    path.line(to: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.minY + rect.height * 0.35))
    path.line(to: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.minY + rect.height * 0.08))
    path.line(to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.42))
    path.close()
    color(1, 1, 1).setFill()
    path.fill()
}

image.lockFocus()

let bounds = CGRect(origin: .zero, size: canvas)
drawLinearGradient(
    in: bounds,
    colors: [
        color(0.06, 0.10, 0.13),
        color(0.13, 0.25, 0.25),
        color(0.56, 0.06, 0.28),
        color(0.08, 0.35, 0.58)
    ],
    angle: 315
)

for blob in [
    (CGRect(x: 585, y: 110, width: 330, height: 330), color(0.03, 0.55, 0.96, 0.50)),
    (CGRect(x: 95, y: 120, width: 330, height: 330), color(0.92, 0.51, 0.05, 0.45)),
    (CGRect(x: 230, y: 600, width: 600, height: 360), color(0.84, 0.00, 0.42, 0.50))
] {
    let gradient = NSGradient(colors: [blob.1, color(0, 0, 0, 0)])!
    gradient.draw(in: NSBezierPath(ovalIn: blob.0), angle: 0)
}

let displayOuter = CGRect(x: 110, y: 284, width: 804, height: 454)
let displayShadow = NSShadow()
displayShadow.shadowColor = color(0, 0, 0, 0.34)
displayShadow.shadowBlurRadius = 46
displayShadow.shadowOffset = CGSize(width: 0, height: -20)
displayShadow.set()

color(0.95, 0.96, 0.94).setFill()
roundedRect(displayOuter, radius: 78).fill()
NSShadow().set()

color(1, 1, 1, 0.62).setStroke()
let outerStroke = roundedRect(displayOuter.insetBy(dx: 10, dy: 10), radius: 68)
outerStroke.lineWidth = 5
outerStroke.stroke()

let screen = CGRect(x: 172, y: 356, width: 680, height: 310)
NSGraphicsContext.current?.saveGraphicsState()
roundedRect(screen, radius: 32).addClip()
drawLinearGradient(
    in: screen,
    colors: [
        color(1.00, 0.75, 0.10),
        color(0.95, 0.05, 0.38),
        color(0.15, 0.55, 0.35),
        color(0.05, 0.12, 0.18)
    ],
    angle: 330
)

let sun = NSBezierPath(ovalIn: CGRect(x: 226, y: 558, width: 78, height: 78))
color(1.0, 0.81, 0.16, 0.95).setFill()
sun.fill()

let hills = NSBezierPath()
hills.move(to: CGPoint(x: screen.minX, y: screen.minY + 92))
hills.curve(to: CGPoint(x: screen.minX + 245, y: screen.minY + 164), controlPoint1: CGPoint(x: screen.minX + 92, y: screen.minY + 145), controlPoint2: CGPoint(x: screen.minX + 150, y: screen.minY + 173))
hills.curve(to: CGPoint(x: screen.maxX, y: screen.minY + 118), controlPoint1: CGPoint(x: screen.minX + 418, y: screen.minY + 146), controlPoint2: CGPoint(x: screen.minX + 500, y: screen.minY + 62))
hills.line(to: CGPoint(x: screen.maxX, y: screen.minY))
hills.line(to: CGPoint(x: screen.minX, y: screen.minY))
hills.close()
color(0.02, 0.22, 0.17, 0.84).setFill()
hills.fill()

var bladeIndex = 0
for x in stride(from: screen.minX + 8, through: screen.maxX - 8, by: 22) {
    let bladeHeight = CGFloat(74 + ((bladeIndex * 37) % 62))
    let line = NSBezierPath()
    line.move(to: CGPoint(x: x, y: screen.minY))
    line.line(to: CGPoint(x: x + 35, y: screen.minY + bladeHeight))
    line.lineWidth = 5
    color(0.10, 0.50, 0.30, 0.42).setStroke()
    line.stroke()
    bladeIndex += 1
}

NSGraphicsContext.current?.restoreGraphicsState()

let screenStroke = roundedRect(screen, radius: 32)
screenStroke.lineWidth = 12
color(1, 1, 1, 0.92).setStroke()
screenStroke.stroke()

let badge = CGRect(x: 670, y: 218, width: 206, height: 206)
let badgeShadow = NSShadow()
badgeShadow.shadowColor = color(0.02, 0.18, 0.40, 0.34)
badgeShadow.shadowBlurRadius = 34
badgeShadow.shadowOffset = CGSize(width: 0, height: -12)
badgeShadow.set()
let badgePath = NSBezierPath(ovalIn: badge)
color(0.04, 0.48, 0.96).setFill()
badgePath.fill()
NSShadow().set()

color(1, 1, 1, 0.22).setStroke()
badgePath.lineWidth = 4
badgePath.stroke()
drawPaperPlane(in: badge.insetBy(dx: 48, dy: 48))

let shine = NSBezierPath()
shine.move(to: CGPoint(x: 120, y: 808))
shine.curve(to: CGPoint(x: 842, y: 862), controlPoint1: CGPoint(x: 340, y: 950), controlPoint2: CGPoint(x: 640, y: 944))
shine.line(to: CGPoint(x: 904, y: 1024))
shine.line(to: CGPoint(x: 0, y: 1024))
shine.line(to: CGPoint(x: 0, y: 880))
shine.close()
color(1, 1, 1, 0.08).setFill()
shine.fill()

image.unlockFocus()

var proposedRect = CGRect(origin: .zero, size: canvas)
guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
      let context = CGContext(
        data: nil,
        width: Int(canvas.width),
        height: Int(canvas.height),
        bitsPerComponent: 8,
        bytesPerRow: Int(canvas.width) * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      ) else {
    fatalError("Could not prepare opaque app icon")
}

context.setFillColor(CGColor(red: 0.06, green: 0.10, blue: 0.13, alpha: 1))
context.fill(bounds)
context.draw(cgImage, in: bounds)

guard let flattenedIcon = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outputPath) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    fatalError("Could not render app icon")
}

CGImageDestinationAddImage(destination, flattenedIcon, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write app icon")
}
