import CredentialStore
import Foundation
import StatusList
import Trust
import WalletAPI

/// The unified EUDI Wallet SDK facade (API-CONTRACT.md §5). Multi-instance; no global state.
///
/// Phase A wires credential storage, DCQL retrieval, and status; issuance/presentation/proximity follow.
public struct Wallet {
    public let credentials: CredentialsService
    private let ports: WalletPorts

    /// Idempotent; no resources held yet.
    public func close() {}

    public static func create(config: WalletConfig, ports: WalletPorts) -> Wallet {
        let clockSeconds: () -> Int64 = { Int64(ports.clock.now().timeIntervalSince1970) }
        let store = DefaultCredentialStore(driver: ports.storage)

        // Lazy anchor source: anchors are only required when a status token is actually verified, so a
        // wallet without configured anchors can still read credentials with no status reference.
        let anchorSource = LazyIssuerAnchorSource(ders: config.trust.issuerAnchorsDer)
        let validator = X509ChainValidator(anchorSource: anchorSource, validationTime: ports.clock.now())
        let statusClient = StatusListClient(http: ports.http, keyResolver: X5cIssuerKeyResolver(validator: validator), clock: clockSeconds)

        return Wallet(credentials: CredentialsService(store: store, statusClient: statusClient), ports: ports)
    }
}

struct LazyIssuerAnchorSource: TrustAnchorSource {
    let ders: [[UInt8]]
    func anchors() async throws -> TrustAnchors {
        guard !ders.isEmpty else { throw WalletFacadeError.noTrustAnchors }
        return try TrustAnchors.ofDer(ders)
    }
}

enum WalletFacadeError: Error { case noTrustAnchors }
