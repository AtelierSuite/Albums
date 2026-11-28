import Engine
import Foundation

@Observable
@MainActor
final class PictureInPictureManager {

    var isActive: Bool = false
    var isPreparing: Bool = false
    let isPossible = false

    func setup() {}

    func start(with image: PlatformImage, restore: @escaping @MainActor () -> Void) {}

    func stop() {}
}
