import CryptoKit
import DeviceCheck
import Foundation
// Re-export so the app (which imports AppleAttestation) can name WalletProviderAttestation /
// DevIntegrityTokenProvider / IntegrityTokenProvider without linking the WalletProvider product directly.
@_exported import WalletProvider

/// App Attest–backed `IntegrityTokenProvider` — the iOS counterpart of android `PlayIntegrityTokenProvider`.
/// Attests the app instance via `DCAppAttestService`; on an unsupported device (Simulator) or any App Attest
/// error it uses `fallback` (the dev integrity token), matching the android side-loaded fallback.
///
/// Note: the wire format of the returned token must match what the Wallet Provider backend verifies for iOS;
/// until that is confirmed, wire `DevIntegrityTokenProvider()` directly (which the backend accepts in debug,
/// as it does for a side-loaded Android build).
public struct AppAttestIntegrityTokenProvider: IntegrityTokenProvider {
    private let fallback: (any IntegrityTokenProvider)?

    public init(fallback: (any IntegrityTokenProvider)? = DevIntegrityTokenProvider()) {
        self.fallback = fallback
    }

    public func integrityToken(nonce: String) async throws -> String {
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            if let fallback { return try await fallback.integrityToken(nonce: nonce) }
            throw AttestationError.unsupported
        }
        do {
            let keyId = try await service.generateKey()
            let clientDataHash = Data(SHA256.hash(data: Data(nonce.utf8)))
            let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
            let payload: [String: String] = [
                "keyId": keyId,
                "attestation": attestation.base64EncodedString(),
                "nonce": nonce,
            ]
            let json = try JSONSerialization.data(withJSONObject: payload)
            return "appattest:" + json.base64EncodedString()
        } catch {
            if let fallback { return try await fallback.integrityToken(nonce: nonce) }
            throw error
        }
    }

    enum AttestationError: Error { case unsupported }
}
