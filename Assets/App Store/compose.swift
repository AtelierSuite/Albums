#!/usr/bin/env swift

import AppKit

// Frames the raw captures in Raw/<device>/<language>/ for the App Store and
// writes them to <device>/<language>/. Colours, fonts and layout follow the
// Pixelmator documents in Assets/.
// Usage: ./compose.swift [iPhone|iPad|Mac ...]   (defaults to all three)

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let languages = ["en", "ja"]
let requestedDevices = Set(CommandLine.arguments.dropFirst())

enum Device: String {
    case iPhone
    case iPad
    case mac = "Mac"

    var canvasSize: NSSize {
        switch self {
        case .iPhone: NSSize(width: 1284, height: 2778)
        case .iPad: NSSize(width: 2048, height: 2732)
        case .mac: NSSize(width: 1440, height: 900)
        }
    }

    var outputScale: CGFloat { self == .mac ? 2 : 1 }

    /// The Mac's text layers are half the size of the iPhone's and iPad's.
    var textScale: CGFloat { self == .mac ? 0.5 : 1 }

    var isRequested: Bool { requestedDevices.isEmpty || requestedDevices.contains(rawValue) }

    func rawDir(_ language: String) -> URL {
        scriptDir.appendingPathComponent("Raw").appendingPathComponent(rawValue)
            .appendingPathComponent(language)
    }

    func outDir(_ language: String) -> URL {
        scriptDir.appendingPathComponent(rawValue).appendingPathComponent(language)
    }
}

struct Copy {
    let header: String
    let caption: String
}

struct Screenshot {
    let name: String
    let copy: [String: Copy]
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// The purple the Background Color adjustment gives the gradient in the Pixelmator documents.
let gradientTop = color(0x5635BA)
let gradientBottom = color(0x868CDE)
let iPadGradientTop = color(0x512CB5)

let collectionCopy = [
    "en": Copy(header: "Your second photos library", caption: "Memes, scans, receipts, and more"),
    "ja": Copy(header: "もう一つの写真ライブラリ", caption: "イラスト、スクショ、レシートなど")
]
let nestedCopy = [
    "en": Copy(header: "Nested albums", caption: "Group related photos together"),
    "ja": Copy(header: "アルバムにアルバム！？", caption: "関連するアルバムと画像を簡単にグループ化")
]
let duplicatesCopy = [
    "en": Copy(header: "Find duplicates in seconds", caption: "Fast, and completely offline"),
    "ja": Copy(header: "重複をすぐに発見", caption: "数秒で見つけて、完全にオフラインで動作")
]

let iPhoneScreenshots = [
    Screenshot(name: "01-collection", copy: collectionCopy),
    Screenshot(name: "02-nested", copy: nestedCopy),
    Screenshot(
        name: "03-libraries",
        copy: [
            "en": Copy(header: "A library for everything", caption: "Keep each one on device or in iCloud"),
            "ja": Copy(header: "ライブラリで使い分け", caption: "端末内にもiCloudにも、用途ごとに整理")
        ]
    ),
    Screenshot(
        name: "04-viewer",
        copy: [
            "en": Copy(header: "View, copy, share", caption: "Easily copy or share a photo"),
            "ja": Copy(header: "閲覧、コピー、共有", caption: "ビューワーから簡単にコピー")
        ]
    ),
    Screenshot(name: "05-duplicates", copy: duplicatesCopy)
]

let largeScreenshots = [
    Screenshot(name: "01-collection", copy: collectionCopy),
    Screenshot(name: "02-nested", copy: nestedCopy),
    Screenshot(name: "03-duplicates", copy: duplicatesCopy)
]

// MARK: - Text

func headlineFont(ofSize size: CGFloat, weight: NSFont.Weight, language: String) -> NSFont {
    if language == "ja", let font = NSFont(name: "TsukuARdGothic-Bold", size: size) {
        return font
    }
    let system = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
    let rounded = system.withDesign(.rounded) ?? system
    return NSFont(descriptor: rounded, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
}

struct Line {
    let text: String
    let attributes: [NSAttributedString.Key: Any]
    let size: NSSize

    init(_ text: String, size: CGFloat, weight: NSFont.Weight, language: String, maxWidth: CGFloat) {
        var fontSize = size
        var attributes: [NSAttributedString.Key: Any] = [:]
        var lineSize = NSSize.zero
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
        shadow.shadowBlurRadius = size * 0.12
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.04)
        while fontSize > 10 {
            attributes = [
                .font: headlineFont(ofSize: fontSize, weight: weight, language: language),
                .foregroundColor: NSColor.white,
                .kern: -2 * fontSize / size,
                .shadow: shadow
            ]
            lineSize = (text as NSString).size(withAttributes: attributes)
            if lineSize.width <= maxWidth { break }
            fontSize -= 2
        }
        self.text = text
        self.attributes = attributes
        self.size = lineSize
    }

    func draw(centerY: CGFloat, canvasWidth: CGFloat) {
        (text as NSString).draw(
            at: NSPoint(x: (canvasWidth - size.width) / 2, y: centerY - size.height / 2),
            withAttributes: attributes
        )
    }
}

func drawHeadline(_ copy: Copy, language: String, device: Device, centerFromTop: CGFloat) {
    let canvas = device.canvasSize
    let scale = device.textScale
    let isJapanese = language == "ja"
    let maxWidth = canvas.width - 120 * scale * (device == .mac ? 4 : 1)
    let header = Line(copy.header, size: (isJapanese ? 76.5 : 92) * scale, weight: .bold,
                      language: language, maxWidth: maxWidth)
    let caption = Line(copy.caption, size: (isJapanese ? 53.2 : 64) * scale, weight: .medium,
                       language: language, maxWidth: maxWidth)
    // The Pixelmator text layers put the two lines' centres about 100 points apart.
    let lineDistance = max(100 * scale, (header.size.height + caption.size.height) / 2)
    let center = canvas.height - centerFromTop
    header.draw(centerY: center + lineDistance / 2, canvasWidth: canvas.width)
    caption.draw(centerY: center - lineDistance / 2, canvasWidth: canvas.width)
}

// MARK: - Images

func cgImage(of image: NSImage) -> CGImage? {
    image.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

func drawFilled(_ raw: CGImage, in rect: CGRect, context: CGContext) {
    let rawSize = CGSize(width: raw.width, height: raw.height)
    let scale = max(rect.width / rawSize.width, rect.height / rawSize.height)
    let drawSize = CGSize(width: rawSize.width * scale, height: rawSize.height * scale)
    context.draw(raw, in: CGRect(
        x: rect.midX - drawSize.width / 2,
        y: rect.maxY - drawSize.height,
        width: drawSize.width,
        height: drawSize.height
    ))
}

func withShadow(blur: CGFloat, offset: NSSize, alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    draw()
    NSGraphicsContext.current?.restoreGraphicsState()
}

// MARK: - iPhone

let hardwareImage = NSImage(contentsOf: scriptDir.appendingPathComponent("Hardware@2x.png"))
let displayImage = NSImage(contentsOf: scriptDir.appendingPathComponent("Display@2x.png"))

func drawiPhone(raw: NSImage, canvas: NSSize) -> Bool {
    guard let hardwareImage, let displayImage,
          let hardwareCG = cgImage(of: hardwareImage), let displayCG = cgImage(of: displayImage),
          let rawCG = cgImage(of: raw), let context = NSGraphicsContext.current?.cgContext else {
        print("missing Hardware@2x.png or Display@2x.png")
        return false
    }
    let width: CGFloat = 1095
    let scale = width / CGFloat(hardwareCG.width)
    let height = CGFloat(hardwareCG.height) * scale
    let deviceRect = NSRect(x: ((canvas.width - width) / 2).rounded(), y: canvas.height - 416 - height,
                            width: width, height: height)
    let displaySize = NSSize(width: CGFloat(displayCG.width) * scale, height: CGFloat(displayCG.height) * scale)
    let displayRect = NSRect(x: deviceRect.midX - displaySize.width / 2, y: deviceRect.midY - displaySize.height / 2,
                             width: displaySize.width, height: displaySize.height)

    withShadow(blur: 70, offset: NSSize(width: 24, height: -36), alpha: 0.35) {
        hardwareImage.draw(in: deviceRect)
    }
    context.saveGState()
    context.clip(to: displayRect, mask: displayCG)
    drawFilled(rawCG, in: displayRect, context: context)
    context.restoreGState()
    return true
}

// MARK: - iPad

func drawiPad(raw: NSImage, canvas: NSSize) -> Bool {
    guard let rawCG = cgImage(of: raw), let context = NSGraphicsContext.current?.cgContext else { return false }
    let width: CGFloat = 2350
    let bezel: CGFloat = 60
    let screenWidth = width - 2 * bezel
    let screenHeight = screenWidth * CGFloat(rawCG.height) / CGFloat(rawCG.width)
    let height = screenHeight + 2 * bezel
    let rect = NSRect(x: 80, y: canvas.height - 315 - height, width: width, height: height)
    let outerRadius: CGFloat = 130

    withShadow(blur: 60, offset: NSSize(width: 0, height: -24), alpha: 0.35) {
        color(0x1C1C1E).setFill()
        NSBezierPath(roundedRect: rect, xRadius: outerRadius, yRadius: outerRadius).fill()
    }
    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: outerRadius - 3, yRadius: outerRadius - 3)
    rim.lineWidth = 6
    color(0x5A5A5E).setStroke()
    rim.stroke()

    let screenRect = rect.insetBy(dx: bezel, dy: bezel)
    let screenRadius = outerRadius - bezel * 0.8
    context.saveGState()
    NSBezierPath(roundedRect: screenRect, xRadius: screenRadius, yRadius: screenRadius).addClip()
    drawFilled(rawCG, in: screenRect, context: context)
    context.restoreGState()

    // The Gradient Fade layer: the bottom 1000 points fade to black.
    NSGradient(colors: [NSColor.black.withAlphaComponent(0), .black])?
        .draw(in: NSRect(x: 0, y: 0, width: canvas.width, height: 1000), angle: -90)
    return true
}

// MARK: - Mac

func drawMac(raw: NSImage, canvas: NSSize) -> Bool {
    guard let rawCG = cgImage(of: raw), let context = NSGraphicsContext.current?.cgContext else { return false }
    let body = NSRect(x: (canvas.width - 1336) / 2, y: canvas.height - 155 - 900, width: 1336, height: 900)
    let screen = NSRect(x: 80, y: canvas.height - 188 - 832, width: 1280, height: 832)

    withShadow(blur: 40, offset: NSSize(width: 0, height: -16), alpha: 0.35) {
        color(0x1C1C1E).setFill()
        NSBezierPath(roundedRect: body, xRadius: 44, yRadius: 44).fill()
    }
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 42, yRadius: 42)
    rim.lineWidth = 4
    color(0x6A6A70).setStroke()
    rim.stroke()

    context.saveGState()
    NSBezierPath(roundedRect: screen, xRadius: 18, yRadius: 18).addClip()
    NSGradient(colors: [color(0x16207A), color(0x2F4FC9), color(0x6F8BEB)])?.draw(in: screen, angle: -60)
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: screen.minX, y: screen.minY + 260))
    wave.curve(to: NSPoint(x: screen.maxX, y: screen.minY + 620),
               controlPoint1: NSPoint(x: screen.minX + 420, y: screen.minY + 120),
               controlPoint2: NSPoint(x: screen.maxX - 420, y: screen.minY + 760))
    wave.line(to: NSPoint(x: screen.maxX, y: screen.minY + 520))
    wave.curve(to: NSPoint(x: screen.minX, y: screen.minY + 160),
               controlPoint1: NSPoint(x: screen.maxX - 420, y: screen.minY + 640),
               controlPoint2: NSPoint(x: screen.minX + 420, y: screen.minY + 20))
    wave.close()
    color(0xA9BCFF, alpha: 0.35).setFill()
    wave.fill()

    let windowWidth: CGFloat = 1160
    let windowHeight = windowWidth * CGFloat(rawCG.height) / CGFloat(rawCG.width)
    let window = NSRect(x: (canvas.width - windowWidth) / 2, y: canvas.height - 242 - windowHeight,
                        width: windowWidth, height: windowHeight)
    withShadow(blur: 30, offset: NSSize(width: 0, height: -12), alpha: 0.45) {
        NSBezierPath(roundedRect: window, xRadius: 16, yRadius: 16).fill()
    }
    context.saveGState()
    NSBezierPath(roundedRect: window, xRadius: 16, yRadius: 16).addClip()
    context.draw(rawCG, in: window)
    context.restoreGState()
    context.restoreGState()

    let notch = NSRect(x: canvas.width / 2 - 92, y: screen.maxY - 30, width: 184, height: 34)
    color(0x1C1C1E).setFill()
    NSBezierPath(roundedRect: notch, xRadius: 12, yRadius: 12).fill()
    color(0x2C2C30).setFill()
    NSBezierPath(ovalIn: NSRect(x: canvas.width / 2 - 5, y: notch.midY - 3, width: 10, height: 10)).fill()
    return true
}

// MARK: - Composition

func compose(_ shot: Screenshot, language: String, device: Device) -> Bool {
    guard let copy = shot.copy[language] else { return true }
    let rawURL = device.rawDir(language).appendingPathComponent("\(shot.name).png")
    guard let raw = NSImage(contentsOf: rawURL) else {
        print("missing raw capture: \(rawURL.path)")
        return false
    }
    let canvas = device.canvasSize
    let pixels = NSSize(width: canvas.width * device.outputScale, height: canvas.height * device.outputScale)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return false }
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let bounds = NSRect(origin: .zero, size: canvas)
    var drawn: Bool
    switch device {
    case .iPhone:
        NSGradient(starting: gradientTop, ending: gradientBottom)?.draw(in: bounds, angle: -90)
        drawHeadline(copy, language: language, device: device, centerFromTop: 220)
        drawn = drawiPhone(raw: raw, canvas: canvas)
    case .iPad:
        NSGradient(colors: [iPadGradientTop, iPadGradientTop, gradientBottom],
                   atLocations: [0, 0.12, 1], colorSpace: .sRGB)?.draw(in: bounds, angle: -90)
        drawn = drawiPad(raw: raw, canvas: canvas)
        drawHeadline(copy, language: language, device: device, centerFromTop: 170)
    case .mac:
        NSGradient(starting: gradientTop, ending: gradientBottom)?.draw(in: bounds, angle: -90)
        drawHeadline(copy, language: language, device: device, centerFromTop: 83)
        drawn = drawMac(raw: raw, canvas: canvas)
    }
    NSGraphicsContext.restoreGraphicsState()
    guard drawn, let png = bitmap.representation(using: .png, properties: [:]) else { return false }

    let outDir = device.outDir(language)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let outURL = outDir.appendingPathComponent("\(shot.name).png")
    do {
        try png.write(to: outURL)
        print("wrote \(outURL.path.replacingOccurrences(of: scriptDir.path + "/", with: ""))")
        return true
    } catch {
        print("failed to write \(outURL.path): \(error)")
        return false
    }
}

var allOK = true
let sets: [(Device, [Screenshot])] = [(.iPhone, iPhoneScreenshots), (.iPad, largeScreenshots), (.mac, largeScreenshots)]
for language in languages {
    for (device, shots) in sets where device.isRequested {
        for shot in shots {
            allOK = compose(shot, language: language, device: device) && allOK
        }
    }
}
exit(allOK ? 0 : 1)
