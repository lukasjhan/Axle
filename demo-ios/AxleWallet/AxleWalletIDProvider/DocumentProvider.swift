import ExtensionKit
import IdentityDocumentServicesUI
import SwiftUI

/// The Digital Credentials API provider extension — a separate process the OS wakes (not the app) when a website
/// calls `navigator.credentials.get` for an `org-iso-mdoc` document Axle Wallet registered. The scene renders the
/// consent UI; on approval it signs the mdoc DeviceResponse with the credential's Secure Enclave device key (via
/// the shared keychain group) and hands the HPKE-encrypted bytes back to the platform. iOS mirror of android
/// `GetCredentialActivity` — but there is no matcher (the OS owns matching + the picker) and iOS routes only the
/// `org-iso-mdoc` protocol to third-party wallets (OpenID4VP over the browser DC API is Apple-unsupported).
@main
struct AxleDocumentProvider: IdentityDocumentProvider {
    var body: some IdentityDocumentRequestScene {
        ISO18013MobileDocumentRequestScene { context in
            DcApiConsentView(context: context)
        }
    }

    /// The app owns registration (`DcApiRegistrar` runs there on every credential change), so the extension has
    /// nothing to refresh here.
    func performRegistrationUpdates() async {}
}
