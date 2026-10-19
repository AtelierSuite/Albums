public struct RGBColor: Equatable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int

    public init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

extension RGBColor {
    public var saturation: Double {
        let maxC = Double(max(red, green, blue))
        let minC = Double(min(red, green, blue))
        guard maxC > 0 else { return 0 }
        return (maxC - minC) / maxC
    }

    public var brightness: Double {
        Double(max(red, green, blue)) / 255.0
    }

    public var hue: Double {
        let red = Double(red) / 255.0
        let green = Double(green) / 255.0
        let blue = Double(blue) / 255.0
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let delta = maxC - minC
        guard delta > 0 else { return 0 }
        var hue: Double
        if maxC == red {
            hue = (green - blue) / delta
        } else if maxC == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return hue
    }

    public var sortKey: (Int, Double, Double) {
        if saturation < 0.12 {
            return (1, brightness, 0)
        }
        return (0, hue, brightness)
    }
}

public struct PicColors: Equatable, Sendable {
    public let primary: RGBColor
    public let accent: RGBColor
    public let contrasting: RGBColor

    public init(primary: RGBColor, accent: RGBColor, contrasting: RGBColor) {
        self.primary = primary
        self.accent = accent
        self.contrasting = contrasting
    }
}

extension PicColors: Comparable {
    public static func < (lhs: PicColors, rhs: PicColors) -> Bool {
        if lhs.primary.sortKey != rhs.primary.sortKey {
            return lhs.primary.sortKey < rhs.primary.sortKey
        }
        if lhs.accent.sortKey != rhs.accent.sortKey {
            return lhs.accent.sortKey < rhs.accent.sortKey
        }
        return lhs.contrasting.sortKey < rhs.contrasting.sortKey
    }
}
