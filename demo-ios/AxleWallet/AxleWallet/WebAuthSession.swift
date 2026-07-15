import AuthenticationServices
import UIKit

/// Async wrapper over `ASWebAuthenticationSession` — the iOS counterpart of the Android issuance flow's
/// external-browser + deep-link round-trip. It opens the issuer's authorization URL in an in-app Safari
/// and returns the `eu.europa.ec.euidi://authorization?...code=...` redirect the SDK needs for
/// `completeAuthorization`. Same user experience: a browser appears for issuer login, then returns to the app.
@MainActor
final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize(url: URL, callbackScheme: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                self?.session = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL.absoluteString)
                } else {
                    continuation.resume(throwing: error ?? WebAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: WebAuthError.cannotStart)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        // A key window is always on screen while the auth session presents; fall back to any window.
        return windows.first(where: \.isKeyWindow) ?? windows.first!
    }
}

enum WebAuthError: Error {
    case cancelled
    case cannotStart
}
