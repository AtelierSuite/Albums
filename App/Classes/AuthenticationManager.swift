import LocalAuthentication
import SwiftUI

@MainActor @Observable
class AuthenticationManager {

    var isUnlocked: Bool = false
    var isAuthenticating: Bool = false

    #if os(macOS)
    private let policy: LAPolicy = .deviceOwnerAuthentication
    #else
    private let policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
    #endif

    var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(policy, error: nil)
    }

    var biometryType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    func authenticate() {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        var error: NSError?

        guard context.canEvaluatePolicy(policy, error: &error) else {
            #if os(macOS)
            if (error as? LAError)?.code == .passcodeNotSet {
                isUnlocked = true
            }
            #else
            isUnlocked = true
            #endif
            return
        }

        isAuthenticating = true
        let reason = String(localized: "Auth.Reason")

        context.evaluatePolicy(policy,
                               localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if success {
                    self.isUnlocked = true
                }
            }
        }
    }

    func lock() {
        isUnlocked = false
    }
}
