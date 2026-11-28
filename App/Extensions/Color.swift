import Engine
import SwiftUI

#if os(macOS)
import AppKit
typealias XPColor = NSColor
#else
#if canImport(UIKit)
import UIKit
#endif
typealias XPColor = UIColor
#endif

extension Color {
    static func hash(_ text: String) -> Int {
        var hash = 0
        let colorConstant = 131
        let maxSafeValue = Int.max / colorConstant
        for char in text.unicodeScalars {
            if hash > maxSafeValue {
                hash /= colorConstant
            }
            hash = Int(char.value) + ((hash << 5) - hash)
        }
        return abs(hash) % (256*256*256)
    }

    static func gradient(from text: String) -> (primary: Color, secondary: Color) {
        let primaryHash = Color.hash(text)
        let red = max(CGFloat(0.2), CGFloat((primaryHash & 0xFF0000) >> 16) / 255.0)
        let green = max(CGFloat(0.2), CGFloat((primaryHash & 0xFF00) >> 8) / 255.0)
        let blue = max(CGFloat(0.2), CGFloat((primaryHash & 0xFF)) / 255.0)

        let primaryXP = XPColor(red: red, green: green, blue: blue, alpha: 1.0)

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        #if os(macOS)
        primaryXP.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let secondaryXP = NSColor(calibratedHue: (hue + 0.1).truncatingRemainder(dividingBy: 1.0),
                                  saturation: saturation,
                                  brightness: brightness,
                                  alpha: alpha)
        return (Color(nsColor: primaryXP), Color(nsColor: secondaryXP))
        #else
        primaryXP.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let secondaryXP = UIColor(hue: (hue + 0.1).truncatingRemainder(dividingBy: 1.0),
                                  saturation: saturation,
                                  brightness: brightness,
                                  alpha: alpha)
        return (Color(uiColor: primaryXP), Color(uiColor: secondaryXP))
        #endif
    }
}
