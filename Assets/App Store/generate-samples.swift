#!/usr/bin/env swift

import Foundation

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let outDir = scriptDir.appendingPathComponent("Samples/Generated")
let perCategory = 12

struct Generator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0xD1B5_4A32_D192_ED03
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func double(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func chance(_ probability: Double) -> Bool {
        double(0...1) < probability
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[int(0...(items.count - 1))]
    }
}

struct RGB {
    let red: Double, green: Double, blue: Double

    init(_ hex: UInt32) {
        red = Double((hex >> 16) & 0xFF)
        green = Double((hex >> 8) & 0xFF)
        blue = Double(hex & 0xFF)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount)
    }

    var hex: String {
        String(format: "#%02x%02x%02x", Int(red.rounded()), Int(green.rounded()), Int(blue.rounded()))
    }
}

struct Sky {
    let top: RGB, bottom: RGB, sun: RGB, ground: RGB
    let isNight: Bool
}

let skies = [
    Sky(top: RGB(0x2f6fd6), bottom: RGB(0xbfe4ff), sun: RGB(0xfff6d8), ground: RGB(0x23415e), isNight: false),
    Sky(top: RGB(0x5a7fe0), bottom: RGB(0xffd1b0), sun: RGB(0xfff1c4), ground: RGB(0x3a3560), isNight: false),
    Sky(top: RGB(0x3b2a78), bottom: RGB(0xff8a6a), sun: RGB(0xffd27a), ground: RGB(0x2a1c46), isNight: false),
    Sky(top: RGB(0x1d2b64), bottom: RGB(0xf8a3a8), sun: RGB(0xffe0b5), ground: RGB(0x1c1838), isNight: false),
    Sky(top: RGB(0xff7e5f), bottom: RGB(0xfeb47b), sun: RGB(0xfff3d6), ground: RGB(0x5b2a3c), isNight: false),
    Sky(top: RGB(0x7ec8e3), bottom: RGB(0xe8f7f0), sun: RGB(0xffffff), ground: RGB(0x2e5a5a), isNight: false),
    Sky(top: RGB(0x0b1030), bottom: RGB(0x2b3a78), sun: RGB(0xf4f1dc), ground: RGB(0x060818), isNight: true),
    Sky(top: RGB(0x140c2e), bottom: RGB(0x5b3a8c), sun: RGB(0xffeec9), ground: RGB(0x0c0618), isNight: true)
]

let palettes: [[UInt32]] = [
    [0x264653, 0x2a9d8f, 0xe9c46a, 0xf4a261, 0xe76f51],
    [0x3d348b, 0x7678ed, 0xf7b801, 0xf18701, 0xf35b04],
    [0x0b132b, 0x1c2541, 0x3a506b, 0x5bc0be, 0xe0fbfc],
    [0xff595e, 0xffca3a, 0x8ac926, 0x1982c4, 0x6a4c93],
    [0xf72585, 0xb5179e, 0x7209b7, 0x4361ee, 0x4cc9f0],
    [0xfec5bb, 0xfcd5ce, 0xf8edeb, 0xd8e2dc, 0xffe5d9],
    [0x22223b, 0x4a4e69, 0x9a8c98, 0xc9ada7, 0xf2e9e4],
    [0x003049, 0xd62828, 0xf77f00, 0xfcbf49, 0xeae2b7],
    [0x606c38, 0x283618, 0xfefae0, 0xdda15e, 0xbc6c25],
    [0x8ecae6, 0x219ebc, 0x023047, 0xffb703, 0xfb8500],
    [0xcdb4db, 0xffc8dd, 0xffafcc, 0xbde0fe, 0xa2d2ff],
    [0x10002b, 0x3c096c, 0x7b2cbf, 0xc77dff, 0xe0aaff]
]

let landscapeSizes = [(1600, 1200), (1500, 1000), (1600, 900), (1200, 1600), (1200, 1200), (1000, 1500)]
let wallpaperSizes = [(1080, 1920), (1200, 1600), (1200, 1200), (1600, 1200), (1000, 1500)]

final class SVG {
    let width: Double, height: Double
    private var defs: [String] = []
    private var body: [String] = []
    private var gradientCount = 0

    init(width: Int, height: Int) {
        self.width = Double(width)
        self.height = Double(height)
    }

    func linear(_ stops: [(Double, RGB)], vertical: Bool = true, opacity: Double = 1) -> String {
        gradientCount += 1
        let id = "g\(gradientCount)"
        let direction = vertical ? "x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"" : "x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\""
        let stopTags = stops.map {
            "<stop offset=\"\(f($0.0))\" stop-color=\"\($0.1.hex)\" stop-opacity=\"\(f(opacity))\"/>"
        }.joined()
        defs.append("<linearGradient id=\"\(id)\" \(direction)>\(stopTags)</linearGradient>")
        return "url(#\(id))"
    }

    func radial(_ inner: RGB, _ outer: RGB, innerOpacity: Double = 1, outerOpacity: Double = 0) -> String {
        gradientCount += 1
        let id = "g\(gradientCount)"
        defs.append("""
        <radialGradient id="\(id)" cx="0.5" cy="0.5" r="0.5">\
        <stop offset="0" stop-color="\(inner.hex)" stop-opacity="\(f(innerOpacity))"/>\
        <stop offset="1" stop-color="\(outer.hex)" stop-opacity="\(f(outerOpacity))"/>\
        </radialGradient>
        """)
        return "url(#\(id))"
    }

    func add(_ element: String) {
        body.append(element)
    }

    func rect(_ posX: Double, _ posY: Double, _ width: Double, _ height: Double, fill: String,
              opacity: Double = 1, radius: Double = 0) {
        add("<rect x=\"\(f(posX))\" y=\"\(f(posY))\" width=\"\(f(width))\" height=\"\(f(height))\" rx=\"\(f(radius))\" "
            + "fill=\"\(fill)\" opacity=\"\(f(opacity))\"/>")
    }

    func circle(_ posX: Double, _ posY: Double, _ radius: Double, fill: String, opacity: Double = 1) {
        add("<circle cx=\"\(f(posX))\" cy=\"\(f(posY))\" r=\"\(f(radius))\" fill=\"\(fill)\" opacity=\"\(f(opacity))\"/>")
    }

    func path(_ data: String, fill: String, opacity: Double = 1, stroke: String? = nil, strokeWidth: Double = 0) {
        let strokeAttributes = stroke.map { " stroke=\"\($0)\" stroke-width=\"\(f(strokeWidth))\" stroke-linecap=\"round\"" } ?? ""
        add("<path d=\"\(data)\" fill=\"\(fill)\" opacity=\"\(f(opacity))\"\(strokeAttributes)/>")
    }

    var document: String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(width))" height="\(Int(height))" \
        viewBox="0 0 \(Int(width)) \(Int(height))">
          <defs>\(defs.joined(separator: "\n    "))</defs>
          \(body.joined(separator: "\n  "))
        </svg>

        """
    }
}

func f(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
}

func ridge(_ svg: SVG, baseline: Double, amplitude: Double, peaks: Int, jagged: Bool,
           rng: inout Generator) -> String {
    let step = svg.width / Double(peaks)
    var data = "M0 \(f(svg.height)) L0 \(f(baseline - rng.double(0...amplitude)))"
    for index in 1...peaks {
        let posX = Double(index) * step
        let posY = baseline - rng.double(amplitude * 0.2...amplitude)
        if jagged {
            let midX = posX - step / 2 + rng.double(-step * 0.2...step * 0.2)
            data += " L\(f(midX)) \(f(posY)) L\(f(posX)) \(f(baseline - rng.double(0...amplitude * 0.5)))"
        } else {
            data += " Q\(f(posX - step / 2)) \(f(posY - amplitude * 0.3)) \(f(posX)) \(f(baseline - rng.double(0...amplitude * 0.6)))"
        }
    }
    return data + " L\(f(svg.width)) \(f(svg.height)) Z"
}

func backdrop(_ svg: SVG, sky: Sky) {
    svg.rect(0, 0, svg.width, svg.height, fill: svg.linear([(0, sky.top), (1, sky.bottom)]))
}

func stars(_ svg: SVG, count: Int, maxY: Double, rng: inout Generator) {
    for _ in 0..<count {
        svg.circle(rng.double(0...svg.width), rng.double(0...maxY), rng.double(1.2...3.6),
                   fill: "#ffffff", opacity: rng.double(0.35...0.95))
    }
}

func sun(_ svg: SVG, x posX: Double, y posY: Double, radius: Double, color: RGB) {
    svg.circle(posX, posY, radius * 3, fill: svg.radial(color, color, innerOpacity: 0.55, outerOpacity: 0))
    svg.circle(posX, posY, radius, fill: color.hex)
}

func cloud(_ svg: SVG, x posX: Double, y posY: Double, size: Double, color: String, opacity: Double, rng: inout Generator) {
    var data = ""
    let puffs = rng.int(3...5)
    for index in 0..<puffs {
        let centerX = posX + Double(index) * size * 0.55
        let radius = size * rng.double(0.35...0.6)
        data += "M\(f(centerX - radius)) \(f(posY)) a\(f(radius)) \(f(radius)) 0 1 1 \(f(radius * 2)) 0 Z "
    }
    data += "M\(f(posX - size * 0.3)) \(f(posY)) h\(f(Double(puffs) * size * 0.55 + size * 0.1)) "
        + "a\(f(size * 0.25)) \(f(size * 0.25)) 0 0 1 0 \(f(size * 0.3)) h-\(f(Double(puffs) * size * 0.55 + size * 0.1)) "
        + "a\(f(size * 0.25)) \(f(size * 0.25)) 0 0 1 0 -\(f(size * 0.3)) Z"
    svg.path(data, fill: color, opacity: opacity)
}

func mountains(_ svg: SVG, rng: inout Generator) {
    let sky = rng.pick(skies)
    backdrop(svg, sky: sky)
    if sky.isNight { stars(svg, count: 120, maxY: svg.height * 0.6, rng: &rng) }
    sun(svg, x: svg.width * rng.double(0.2...0.8), y: svg.height * rng.double(0.18...0.42),
        radius: min(svg.width, svg.height) * rng.double(0.05...0.09), color: sky.sun)
    let layers = rng.int(3...5)
    for layer in 0..<layers {
        let depth = Double(layer) / Double(layers - 1)
        let color = sky.bottom.mixed(with: sky.ground, 0.25 + depth * 0.75)
        let baseline = svg.height * (0.55 + depth * 0.3)
        svg.path(ridge(svg, baseline: baseline, amplitude: svg.height * (0.28 - depth * 0.15),
                       peaks: rng.int(3...7), jagged: layer < 2 || rng.chance(0.4), rng: &rng),
                 fill: color.hex)
        if layer == 0 && !sky.isNight && rng.chance(0.6) {
            cloud(svg, x: svg.width * rng.double(0.05...0.6), y: svg.height * rng.double(0.15...0.3),
                  size: svg.width * 0.08, color: "#ffffff", opacity: 0.8, rng: &rng)
        }
    }
}

func seaside(_ svg: SVG, rng: inout Generator) {
    let sky = rng.pick(skies)
    let horizon = svg.height * rng.double(0.5...0.62)
    svg.rect(0, 0, svg.width, horizon, fill: svg.linear([(0, sky.top), (1, sky.bottom)]))
    if sky.isNight { stars(svg, count: 90, maxY: horizon * 0.8, rng: &rng) }
    let sunX = svg.width * rng.double(0.3...0.7)
    let radius = min(svg.width, svg.height) * rng.double(0.07...0.12)
    sun(svg, x: sunX, y: horizon - radius * rng.double(0.2...1.6), radius: radius, color: sky.sun)
    if !sky.isNight {
        for _ in 0..<rng.int(1...3) {
            cloud(svg, x: svg.width * rng.double(0...0.8), y: horizon * rng.double(0.15...0.6),
                  size: svg.width * rng.double(0.05...0.09), color: "#ffffff", opacity: 0.75, rng: &rng)
        }
    }
    let water = sky.top.mixed(with: sky.ground, 0.5)
    svg.rect(0, horizon, svg.width, svg.height - horizon,
             fill: svg.linear([(0, sky.bottom.mixed(with: water, 0.6)), (1, water.mixed(with: sky.ground, 0.6))]))
    for row in 0..<14 {
        let posY = horizon + Double(row * row) * (svg.height - horizon) / 196 + 6
        let width = radius * (0.6 + Double(row) * 0.25) * rng.double(0.6...1.2)
        svg.rect(sunX - width / 2 + rng.double(-20...20), posY, width, 4 + Double(row) * 0.6,
                 fill: sky.sun.hex, opacity: 0.6 - Double(row) * 0.035, radius: 3)
    }
    if rng.chance(0.5) {
        let islandX = svg.width * rng.double(0.05...0.6)
        let islandWidth = svg.width * rng.double(0.2...0.4)
        svg.path("M\(f(islandX)) \(f(horizon)) Q\(f(islandX + islandWidth * 0.4)) \(f(horizon - svg.height * 0.08)) "
                 + "\(f(islandX + islandWidth)) \(f(horizon)) Z", fill: sky.ground.mixed(with: sky.bottom, 0.3).hex)
    }
}

func city(_ svg: SVG, rng: inout Generator) {
    let sky = skies[rng.pick([2, 3, 6, 7])]
    backdrop(svg, sky: sky)
    stars(svg, count: sky.isNight ? 80 : 20, maxY: svg.height * 0.45, rng: &rng)
    sun(svg, x: svg.width * rng.double(0.15...0.85), y: svg.height * rng.double(0.12...0.3),
        radius: min(svg.width, svg.height) * 0.05, color: sky.sun)
    let windowColors = [RGB(0xffd97a), RGB(0xffeab0), RGB(0x9fd8ff), RGB(0xff9ec7)]
    for layer in 0..<3 {
        let depth = Double(layer) / 2
        let color = sky.bottom.mixed(with: sky.ground, 0.45 + depth * 0.55)
        var posX = -rng.double(0...40)
        while posX < svg.width {
            let width = svg.width * rng.double(0.06...0.13)
            let height = svg.height * rng.double(0.18...0.5) * (1.1 - depth * 0.35)
            let top = svg.height - height
            svg.rect(posX, top, width - 4, height, fill: color.hex)
            if layer == 2 {
                let windowColor = rng.pick(windowColors).hex
                let columns = max(2, Int(width / 34))
                var posY = top + 24
                while posY < svg.height - 30 {
                    for column in 0..<columns where rng.chance(0.45) {
                        svg.rect(posX + 12 + Double(column) * (width - 24) / Double(columns), posY,
                                 (width - 24) / Double(columns) - 10, 14, fill: windowColor,
                                 opacity: rng.double(0.55...1))
                    }
                    posY += 34
                }
            } else if layer == 1 && rng.chance(0.3) {
                svg.rect(posX + width / 2 - 3, top - 60, 6, 60, fill: color.hex)
                svg.circle(posX + width / 2, top - 62, 6, fill: "#ff5a5a")
            }
            posX += width
        }
    }
}

func forest(_ svg: SVG, rng: inout Generator) {
    let sky = skies[rng.pick([0, 1, 2, 5, 6])]
    backdrop(svg, sky: sky)
    if sky.isNight { stars(svg, count: 100, maxY: svg.height * 0.5, rng: &rng) }
    sun(svg, x: svg.width * rng.double(0.2...0.8), y: svg.height * rng.double(0.15...0.3),
        radius: min(svg.width, svg.height) * 0.06, color: sky.sun)
    let rows = 4
    for row in 0..<rows {
        let depth = Double(row) / Double(rows - 1)
        let green = RGB(0x5f9e6e).mixed(with: RGB(0x0f2e22), depth)
        let color = sky.bottom.mixed(with: green, 0.35 + depth * 0.65)
        let baseline = svg.height * (0.55 + depth * 0.32)
        svg.path(ridge(svg, baseline: baseline + 20, amplitude: svg.height * 0.05, peaks: 4, jagged: false,
                       rng: &rng), fill: color.hex)
        var posX = -rng.double(0...60)
        let treeHeight = svg.height * (0.12 + depth * 0.12)
        while posX < svg.width + 40 {
            let height = treeHeight * rng.double(0.7...1.2)
            let width = height * rng.double(0.45...0.6)
            let base = baseline + rng.double(-10...30)
            svg.path("M\(f(posX)) \(f(base - height)) L\(f(posX + width / 2)) \(f(base)) L\(f(posX - width / 2)) \(f(base)) Z",
                     fill: color.hex)
            posX += width * rng.double(0.6...1.0)
        }
        if row < rows - 1 {
            svg.rect(0, baseline - svg.height * 0.04, svg.width, svg.height * 0.08, fill: "#ffffff",
                     opacity: 0.12, radius: 0)
        }
    }
}

func dunes(_ svg: SVG, rng: inout Generator) {
    let sky = skies[rng.pick([1, 2, 4, 5, 7])]
    backdrop(svg, sky: sky)
    if sky.isNight { stars(svg, count: 140, maxY: svg.height * 0.55, rng: &rng) }
    sun(svg, x: svg.width * rng.double(0.2...0.8), y: svg.height * rng.double(0.2...0.4),
        radius: min(svg.width, svg.height) * rng.double(0.06...0.1), color: sky.sun)
    let sand = sky.isNight ? RGB(0x5a4a7a) : RGB(0xf2b880)
    let shadow = sky.isNight ? RGB(0x1a1230) : RGB(0xa4553a)
    for layer in 0..<4 {
        let depth = Double(layer) / 3
        let color = sand.mixed(with: shadow, depth * 0.7).mixed(with: sky.bottom, (1 - depth) * 0.3)
        let baseline = svg.height * (0.58 + depth * 0.28)
        let crest = svg.width * rng.double(0.2...0.8)
        let data = "M0 \(f(svg.height)) L0 \(f(baseline)) C\(f(crest * 0.5)) \(f(baseline - svg.height * 0.12)) "
            + "\(f(crest)) \(f(baseline - svg.height * 0.14)) \(f(crest + svg.width * 0.1)) \(f(baseline - svg.height * 0.02)) "
            + "S\(f(svg.width * 0.9)) \(f(baseline + svg.height * 0.02)) \(f(svg.width)) \(f(baseline - svg.height * 0.06)) "
            + "L\(f(svg.width)) \(f(svg.height)) Z"
        svg.path(data, fill: color.hex)
    }
}

func aurora(_ svg: SVG, rng: inout Generator) {
    let top = RGB(rng.pick([0x040b1f, 0x070720, 0x02121a]))
    svg.rect(0, 0, svg.width, svg.height, fill: svg.linear([(0, top), (1, RGB(0x10204a))]))
    stars(svg, count: 180, maxY: svg.height, rng: &rng)
    let bands = [RGB(0x3dffb0), RGB(0x6af7ff), RGB(0xb07cff), RGB(0xff7ce0)]
    for index in 0..<rng.int(3...5) {
        let color = bands[(index + rng.int(0...3)) % bands.count]
        let posY = svg.height * rng.double(0.2...0.5)
        let thickness = svg.height * rng.double(0.08...0.18)
        let wave = svg.height * rng.double(0.05...0.15)
        let data = "M0 \(f(posY)) C\(f(svg.width * 0.3)) \(f(posY - wave)) \(f(svg.width * 0.6)) \(f(posY + wave)) \(f(svg.width)) \(f(posY - wave * 0.5)) "
            + "L\(f(svg.width)) \(f(posY - wave * 0.5 + thickness)) C\(f(svg.width * 0.6)) \(f(posY + wave + thickness * 1.4)) "
            + "\(f(svg.width * 0.3)) \(f(posY - wave + thickness * 0.6)) 0 \(f(posY + thickness)) Z"
        svg.path(data, fill: svg.linear([(0, color), (1, color.mixed(with: top, 0.8))], opacity: 0.5))
    }
    let ground = RGB(0x050812)
    svg.path(ridge(svg, baseline: svg.height * 0.86, amplitude: svg.height * 0.16, peaks: rng.int(4...7),
                   jagged: true, rng: &rng), fill: ground.mixed(with: top, 0.4).hex)
    svg.path(ridge(svg, baseline: svg.height * 0.95, amplitude: svg.height * 0.06, peaks: 5, jagged: false,
                   rng: &rng), fill: ground.hex)
}

func space(_ svg: SVG, rng: inout Generator) {
    let palette = rng.pick(palettes).map(RGB.init)
    svg.rect(0, 0, svg.width, svg.height, fill: svg.linear([(0, RGB(0x05040f)), (1, RGB(0x1a1035))]))
    svg.circle(svg.width * rng.double(0.2...0.8), svg.height * rng.double(0.2...0.8), max(svg.width, svg.height) * 0.4,
               fill: svg.radial(palette[1], palette[1], innerOpacity: 0.35, outerOpacity: 0))
    stars(svg, count: 220, maxY: svg.height, rng: &rng)
    let posX = svg.width * rng.double(0.3...0.7), posY = svg.height * rng.double(0.35...0.65)
    let radius = min(svg.width, svg.height) * rng.double(0.18...0.28)
    let tilt = rng.double(-25...(-8))
    let ringColor = palette[3].hex
    svg.add("<ellipse cx=\"\(f(posX))\" cy=\"\(f(posY))\" rx=\"\(f(radius * 1.9))\" ry=\"\(f(radius * 0.45))\" fill=\"none\" "
            + "stroke=\"\(ringColor)\" stroke-width=\"\(f(radius * 0.12))\" opacity=\"0.5\" transform=\"rotate(\(f(tilt)) \(f(posX)) \(f(posY)))\"/>")
    svg.circle(posX, posY, radius, fill: svg.linear([(0, palette[2]), (0.5, palette[3]), (1, palette[0])], vertical: false))
    for band in 0..<4 {
        svg.add("<ellipse cx=\"\(f(posX))\" cy=\"\(f(posY - radius * 0.5 + Double(band) * radius * 0.35))\" rx=\"\(f(radius * 0.92))\" "
                + "ry=\"\(f(radius * 0.06))\" fill=\"#ffffff\" opacity=\"0.12\" transform=\"rotate(\(f(tilt)) \(f(posX)) \(f(posY)))\"/>")
    }
    svg.add("<path d=\"M\(f(posX - radius * 1.9)) \(f(posY)) A\(f(radius * 1.9)) \(f(radius * 0.45)) 0 0 0 \(f(posX + radius * 1.9)) \(f(posY))\" "
            + "fill=\"none\" stroke=\"\(ringColor)\" stroke-width=\"\(f(radius * 0.12))\" opacity=\"0.85\" "
            + "transform=\"rotate(\(f(tilt)) \(f(posX)) \(f(posY)))\"/>")
    for _ in 0..<rng.int(1...3) {
        let moon = rng.pick(palette)
        svg.circle(svg.width * rng.double(0.05...0.95), svg.height * rng.double(0.05...0.95),
                   radius * rng.double(0.08...0.2), fill: svg.linear([(0, moon), (1, moon.mixed(with: RGB(0x000000), 0.6))],
                                                                     vertical: false))
    }
}

func blobs(_ svg: SVG, rng: inout Generator) {
    let palette = rng.pick(palettes).map(RGB.init)
    svg.rect(0, 0, svg.width, svg.height, fill: svg.linear([(0, palette[0]), (1, palette[1])], vertical: false))
    for _ in 0..<rng.int(6...10) {
        let color = rng.pick(palette)
        svg.circle(svg.width * rng.double(-0.1...1.1), svg.height * rng.double(-0.1...1.1),
                   max(svg.width, svg.height) * rng.double(0.2...0.5),
                   fill: svg.radial(color, color, innerOpacity: rng.double(0.6...0.95), outerOpacity: 0))
    }
    for _ in 0..<rng.int(2...4) {
        let color = rng.pick(palette)
        svg.circle(svg.width * rng.double(0...1), svg.height * rng.double(0...1),
                   min(svg.width, svg.height) * rng.double(0.08...0.2),
                   fill: svg.linear([(0, color.mixed(with: RGB(0xffffff), 0.4)), (1, color)], vertical: false),
                   opacity: rng.double(0.7...0.95))
    }
}

func waves(_ svg: SVG, rng: inout Generator) {
    let palette = rng.pick(palettes).map(RGB.init)
    let count = rng.int(6...10)
    svg.rect(0, 0, svg.width, svg.height, fill: palette[0].hex)
    let amplitude = svg.height * rng.double(0.02...0.06)
    for index in 0..<count {
        let progress = Double(index) / Double(count)
        let color = palette[index % palette.count].mixed(with: palette[(index + 1) % palette.count], 0.3)
        let posY = svg.height * (0.1 + progress * 0.9)
        let phase = rng.double(0...1)
        var data = "M0 \(f(svg.height)) L0 \(f(posY))"
        let segments = rng.int(2...4)
        for segment in 0..<segments {
            let startX = svg.width * Double(segment) / Double(segments)
            let endX = svg.width * Double(segment + 1) / Double(segments)
            let direction = (segment + Int(phase * 2)) % 2 == 0 ? -1.0 : 1.0
            data += " C\(f(startX + (endX - startX) * 0.35)) \(f(posY + amplitude * direction)) "
                + "\(f(startX + (endX - startX) * 0.65)) \(f(posY + amplitude * direction)) \(f(endX)) \(f(posY))"
        }
        data += " L\(f(svg.width)) \(f(svg.height)) Z"
        svg.path(data, fill: svg.linear([(0, color.mixed(with: RGB(0xffffff), 0.15)), (1, color)]))
    }
}

func bauhaus(_ svg: SVG, rng: inout Generator) {
    let palette = rng.pick(palettes).map(RGB.init)
    let columns = rng.int(3...5)
    let tile = svg.width / Double(columns)
    let rows = Int((svg.height / tile).rounded(.up))
    svg.rect(0, 0, svg.width, svg.height, fill: palette[4].mixed(with: RGB(0xffffff), 0.5).hex)
    for row in 0..<rows {
        for column in 0..<columns {
            let posX = Double(column) * tile, posY = Double(row) * tile
            let background = rng.pick(palette)
            var foreground = rng.pick(palette)
            if foreground.hex == background.hex { foreground = foreground.mixed(with: RGB(0xffffff), 0.6) }
            svg.rect(posX, posY, tile, tile, fill: background.hex)
            switch rng.int(0...5) {
            case 0:
                svg.circle(posX + tile / 2, posY + tile / 2, tile * 0.38, fill: foreground.hex)
            case 1:
                let corner = rng.int(0...3)
                let left = corner % 2 == 0, top = corner < 2
                let centerX = left ? posX : posX + tile, centerY = top ? posY : posY + tile
                let sweep = left == top ? 1 : 0
                svg.path("M\(f(centerX)) \(f(centerY)) L\(f(left ? posX + tile : posX)) \(f(centerY)) "
                         + "A\(f(tile)) \(f(tile)) 0 0 \(sweep) \(f(centerX)) \(f(top ? posY + tile : posY)) Z", fill: foreground.hex)
            case 2:
                svg.path("M\(f(posX)) \(f(posY + tile)) L\(f(posX + tile / 2)) \(f(posY)) L\(f(posX + tile)) \(f(posY + tile)) Z", fill: foreground.hex)
            case 3:
                svg.path("M\(f(posX)) \(f(posY + tile / 2)) A\(f(tile / 2)) \(f(tile / 2)) 0 0 1 \(f(posX + tile)) \(f(posY + tile / 2)) Z",
                         fill: foreground.hex)
            case 4:
                for stripe in 0..<4 {
                    svg.rect(posX, posY + Double(stripe) * tile / 4 + tile / 16, tile, tile / 8, fill: foreground.hex)
                }
            default:
                svg.circle(posX + tile / 2, posY + tile / 2, tile * 0.4, fill: foreground.hex)
                svg.circle(posX + tile / 2, posY + tile / 2, tile * 0.2, fill: background.hex)
            }
        }
    }
}

struct Category {
    let name: String
    let sizes: [(Int, Int)]
    let draw: (SVG, inout Generator) -> Void

    init(_ name: String, _ sizes: [(Int, Int)], _ draw: @escaping (SVG, inout Generator) -> Void) {
        self.name = name
        self.sizes = sizes
        self.draw = draw
    }
}

let categories: [Category] = [
    Category("mountains", landscapeSizes, mountains),
    Category("seaside", landscapeSizes, seaside),
    Category("city", landscapeSizes, city),
    Category("forest", landscapeSizes, forest),
    Category("dunes", landscapeSizes, dunes),
    Category("aurora", wallpaperSizes, aurora),
    Category("space", wallpaperSizes, space),
    Category("blobs", wallpaperSizes, blobs),
    Category("waves", wallpaperSizes, waves),
    Category("bauhaus", wallpaperSizes, bauhaus)
]

try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
var names: [String] = []
for (categoryIndex, category) in categories.enumerated() {
    for index in 1...perCategory {
        var rng = Generator(seed: UInt64(categoryIndex * 1000 + index))
        let size = rng.pick(category.sizes)
        let svg = SVG(width: size.0, height: size.1)
        category.draw(svg, &rng)
        let fileName = String(format: "%@-%02d", category.name, index)
        try svg.document.write(to: outDir.appendingPathComponent("\(fileName).svg"), atomically: true, encoding: .utf8)
        names.append(fileName)
    }
}
print(names.joined(separator: "\n"))
