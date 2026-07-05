import Foundation

/// Typed issuance errors (API-CONTRACT.md §8). Spec error codes are preserved on the relevant cases.
public enum IssuanceError: Error, Equatable {
    case invalidOffer(String)
    case authorizationFailed(oauthError: String?, message: String)
    case credentialRequestFailed(String)
    case deferredNotReady
    case unexpected(String)
}
