import Foundation

enum MacText {

    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: "Mac")
    }
}
