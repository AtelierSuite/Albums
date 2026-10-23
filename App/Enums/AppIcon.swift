import Foundation

enum AppIcon: String, CaseIterable, Identifiable {
    case vivid = "Vivid"
    case pastelRainbow = "PastelRainbow"
    case rainbowHeart = "RainbowHeart"
    case orchid = "Orchid"
    case sunrise = "Sunrise"
    case lagoon = "Lagoon"
    case honey = "Honey"
    case jade = "Jade"
    case azure = "Azure"
    case coral = "Coral"

    init(alternateIconName: String?) {
        self = AppIcon.allCases.first { $0.alternateIconName == alternateIconName } ?? .vivid
    }

    var id: String { rawValue }

    var alternateIconName: String? {
        self == .vivid ? nil : "AppIcon.\(rawValue)"
    }

    var previewImageName: String {
        "AppIconPreview.\(rawValue)"
    }

    var localizedName: String {
        switch self {
        case .vivid: String(localized: "AppIcon.Vivid", table: "More")
        case .pastelRainbow: String(localized: "AppIcon.PastelRainbow", table: "More")
        case .rainbowHeart: String(localized: "AppIcon.RainbowHeart", table: "More")
        case .orchid: String(localized: "AppIcon.Orchid", table: "More")
        case .sunrise: String(localized: "AppIcon.Sunrise", table: "More")
        case .lagoon: String(localized: "AppIcon.Lagoon", table: "More")
        case .honey: String(localized: "AppIcon.Honey", table: "More")
        case .jade: String(localized: "AppIcon.Jade", table: "More")
        case .azure: String(localized: "AppIcon.Azure", table: "More")
        case .coral: String(localized: "AppIcon.Coral", table: "More")
        }
    }
}
