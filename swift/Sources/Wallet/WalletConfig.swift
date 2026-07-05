import Foundation

/// Immutable wallet configuration. Trust anchors are passed as DER so the public API stays free of
/// trust-module types.
public struct WalletConfig {
    public let issuance: IssuanceConfig
    public let presentation: PresentationConfig
    public let trust: TrustConfig

    public init(issuance: IssuanceConfig = IssuanceConfig(),
                presentation: PresentationConfig = PresentationConfig(),
                trust: TrustConfig = TrustConfig()) {
        self.issuance = issuance
        self.presentation = presentation
        self.trust = trust
    }
}

public struct IssuanceConfig {
    public let clientId: String
    public init(clientId: String = "wallet-dev") { self.clientId = clientId }
}

public struct PresentationConfig {
    public init() {}
}

/// Trust anchors as DER — the facade builds trust validators internally per port.
public struct TrustConfig {
    public let issuerAnchorsDer: [[UInt8]]
    public let readerAnchorsDer: [[UInt8]]
    public init(issuerAnchorsDer: [[UInt8]] = [], readerAnchorsDer: [[UInt8]] = []) {
        self.issuerAnchorsDer = issuerAnchorsDer
        self.readerAnchorsDer = readerAnchorsDer
    }
}
