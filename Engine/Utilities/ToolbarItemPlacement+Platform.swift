import SwiftUI

extension ToolbarItemPlacement {

    public static var sheetLeading: ToolbarItemPlacement {
        #if os(macOS)
        .cancellationAction
        #else
        .topBarLeading
        #endif
    }

    public static var sheetTrailing: ToolbarItemPlacement {
        #if os(macOS)
        .confirmationAction
        #else
        .topBarTrailing
        #endif
    }

    public static var sheetBottom: ToolbarItemPlacement {
        #if os(macOS)
        .confirmationAction
        #else
        .bottomBar
        #endif
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    public func titleBackgroundHiddenOnMac() -> some ToolbarContent {
        #if os(macOS)
        sharedBackgroundVisibility(.hidden)
        #else
        self
        #endif
    }
}
