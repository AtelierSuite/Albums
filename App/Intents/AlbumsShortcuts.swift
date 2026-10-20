import AppIntents

struct AlbumsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAlbumIntent(),
            phrases: [
                "Open \(\.$album) in \(.applicationName)",
                "Show \(\.$album) in \(.applicationName)",
                "Open an album in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("OpenAlbum.Title", table: "Intents"),
            systemImageName: "rectangle.stack"
        )
        AppShortcut(
            intent: OpenLibraryIntent(),
            phrases: [
                "Open the \(\.$library) library in \(.applicationName)",
                "Switch to \(\.$library) in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("OpenLibrary.Title", table: "Intents"),
            systemImageName: "square.stack.3d.up"
        )
        AppShortcut(
            intent: GetRandomPicIntent(),
            phrases: [
                "Get a random pic from \(\.$album) in \(.applicationName)",
                "Show me a random pic in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("GetRandomPic.Title", table: "Intents"),
            systemImageName: "shuffle"
        )
        AppShortcut(
            intent: SaveImagesIntent(),
            phrases: [
                "Save images to \(\.$album) in \(.applicationName)",
                "Save to \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("SaveImages.Title", table: "Intents"),
            systemImageName: "square.and.arrow.down"
        )
        AppShortcut(
            intent: CreateAlbumIntent(),
            phrases: [
                "Create an album in \(.applicationName)",
                "Make a new album in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("CreateAlbum.Title", table: "Intents"),
            systemImageName: "rectangle.stack.badge.plus"
        )
    }
}
