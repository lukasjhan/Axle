import AppleCore
import Foundation
import LocalAuthentication

/// Face ID / Touch ID confirmation for the DC API provider extension, mirroring the app's present flows (which
/// gate sharing on `WalletSecurity.biometricEnabled` + `BiometricAuth`). The extension is a separate process and
/// can't read the app's `standard` defaults, so it reads the biometric preference from the shared App Group (the
/// app mirrors it there via `WalletSecurity.syncSharedGroup`).
enum ExtensionBiometrics {
    /// Must match `WalletSecurity.biometricKey`.
    private static let biometricKey = "wallet.biometric"

    /// Whether the user asked to confirm sharing with biometrics AND the device can prompt for one right now.
    static var required: Bool {
        let enabled = UserDefaults(suiteName: AppleSharedGroups.appGroup)?.bool(forKey: biometricKey) ?? false
        return enabled && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Prompt for the enrolled biometric; returns whether the user authenticated. Never throws.
    static func authenticate(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let context = LAContext()
            context.localizedFallbackTitle = "Use passcode"
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in
                continuation.resume(returning: ok)
            }
        }
    }
}
