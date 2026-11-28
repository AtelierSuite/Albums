import SwiftUI

struct ToolbarSpacer: ToolbarContent {

    private let placement: ToolbarItemPlacement

    // Flexible spacers lay out iOS bottom bars; in a Mac toolbar they would scatter buttons across the window.
    init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic) {
        self.placement = placement
    }

    var body: some ToolbarContent {
        SwiftUI.ToolbarSpacer(.fixed, placement: placement)
    }
}
