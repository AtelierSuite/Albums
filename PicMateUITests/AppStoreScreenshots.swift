import XCTest

/// Stages and captures the App Store screenshots.
///
/// Driven by `Assets/App Store/capture.sh` and `capture-mac.sh`, which seed the
/// sample library and say where to write through `SCREENSHOT_DIR` and which
/// language to use through `SCREENSHOT_LANGUAGE`. Without them the test skips.
@MainActor
final class AppStoreScreenshots: XCTestCase {

    private enum Step {
        case openAlbum(english: String, japanese: String)
        case openPic(english: String, japanese: String)
        case back
        case findDuplicates
    }

    private struct Shot {
        let name: String
        let steps: [Step]
    }

    private static let abydos = Step.openAlbum(english: "Abydos", japanese: "アビドス")
    private static let downloads = Step.openAlbum(english: "Downloads", japanese: "ダウンロード")

    private static let iPhoneShots = [
        Shot(name: "01-collection", steps: []),
        Shot(name: "02-nested", steps: [abydos]),
        Shot(name: "03-libraries", steps: [.back]),
        Shot(name: "04-viewer", steps: [.openPic(english: "Beach day", japanese: "海の日")]),
        Shot(name: "05-duplicates", steps: [downloads, .findDuplicates])
    ]

    private static let iPadShots = [
        Shot(name: "01-collection", steps: [.openPic(english: "Beach day", japanese: "海の日")]),
        Shot(name: "02-nested", steps: [abydos, .openPic(english: "Abydos at noon", japanese: "昼のアビドス")]),
        Shot(name: "03-duplicates", steps: [downloads, .findDuplicates])
    ]

    private var directory: URL?
    private var language = "en"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("run through Assets/App Store/capture.sh")
        }
        directory = URL(fileURLWithPath: path)
        language = environment["SCREENSHOT_LANGUAGE"] ?? "en"
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func testScreens() throws {
        for shot in shots {
            launch()
            for step in shot.steps {
                try perform(step)
            }
            Thread.sleep(forTimeInterval: 2)
            try save(shot.name)
        }
    }

    private var shots: [Shot] {
#if targetEnvironment(macCatalyst)
        Self.iPadShots
#else
        UIDevice.current.userInterfaceIdiom == .pad ? Self.iPadShots : Self.iPhoneShots
#endif
    }

    // MARK: - Steps

    private func launch() {
        app = XCUIApplication()
        let locale = language == "ja" ? "ja_JP" : "en_US"
        app.launchArguments += [
            "-ScreenshotMode", "YES",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
#if targetEnvironment(macCatalyst)
        app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
#endif
        app.launch()
        let firstAlbum = app.buttons[language == "ja" ? "アビドス" : "Abydos"].firstMatch
        XCTAssertTrue(firstAlbum.waitForExistence(timeout: 30), "the sample library never appeared")
    }

    private func perform(_ step: Step) throws {
        switch step {
        case .openAlbum(let english, let japanese):
            let album = app.buttons[language == "ja" ? japanese : english].firstMatch
            XCTAssertTrue(album.waitForExistence(timeout: 10), "missing album \(english)")
            album.tap()
            Thread.sleep(forTimeInterval: 1.5)
        case .openPic(let english, let japanese):
            let name = language == "ja" ? japanese : english
            let pic = app.descendants(matching: .any)["pic:\(name)"].firstMatch
            XCTAssertTrue(pic.waitForExistence(timeout: 10), "missing pic \(name)")
            pic.tap()
        case .back:
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5), "no back button")
            back.tap()
            let library = app.buttons["library:__default__"]
            XCTAssertTrue(library.waitForExistence(timeout: 10), "the libraries list never appeared")
        case .findDuplicates:
            let findLabel = language == "ja" ? "重複を整理" : "Organize Duplicates"
            let identified = app.buttons["findDuplicates"].firstMatch
            let find = identified.exists ? identified : app.buttons[findLabel].firstMatch
            let filter = app.buttons["filterMenu"].firstMatch
            let sectionMenus = app.buttons.matching(identifier: "sectionMenu")
            if !find.waitForExistence(timeout: 2) {
                if filter.exists {
                    filter.tap()
                } else if sectionMenus.count > 0 {
                    sectionMenus.element(boundBy: sectionMenus.count - 1).tap()
                }
            }
            XCTAssertTrue(find.waitForExistence(timeout: 5), "missing Find Duplicates")
            find.tap()
            let start = app.buttons["startDuplicateScan"].firstMatch
            XCTAssertTrue(start.waitForExistence(timeout: 5), "missing Start Scan")
            start.tap()
            let deadline = Date().addingTimeInterval(60)
            while start.exists, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.5)
            }
            Thread.sleep(forTimeInterval: 3)
        }
    }

    private func save(_ name: String) throws {
#if targetEnvironment(macCatalyst)
        let screenshot = app.windows.firstMatch.screenshot()
#else
        let screenshot = XCUIScreen.main.screenshot()
#endif
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory {
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}
