package com.hopae.eudi.wallet

/**
 * Immutable wallet configuration. HAIP defaults (PAR/DPoP Required) live in the sub-configs.
 * Trust anchors are passed as DER so the public API stays free of trust-module types.
 */
class WalletConfig(
    val issuance: IssuanceConfig = IssuanceConfig(),
    val presentation: PresentationConfig = PresentationConfig(),
    val trust: TrustConfig = TrustConfig(),
)

class IssuanceConfig(
    val clientId: String = "wallet-dev",
    // Phase B: clientAuth (None | AttestationBased), redirectUri, par/dpop policy.
)

class PresentationConfig(
    // Phase C: clientIdPrefixes, responseEncryption.
)

/** Trust anchors as DER — the facade builds trust validators internally per port. */
class TrustConfig(
    val issuerAnchorsDer: List<ByteArray> = emptyList(),
    val readerAnchorsDer: List<ByteArray> = emptyList(),
)
