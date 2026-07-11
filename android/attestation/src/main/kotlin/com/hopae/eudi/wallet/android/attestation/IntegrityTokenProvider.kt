package com.hopae.eudi.wallet.android.attestation

/**
 * Produces a **device/app integrity** token for wallet-instance registration, bound to the wallet
 * provider's challenge [nonce]. On Android this wraps Play Integrity; on iOS, App Attest. The reference
 * [WalletProviderAttestation] adapter sends whatever this returns to `POST /wallet-instances`, where the
 * backend verifies it. This is an internal concern of the reference adapter, not an SDK port — a customer
 * with their own wallet-provider implements their own `WalletAttestationProvider` and handles integrity
 * however their backend expects.
 */
fun interface IntegrityTokenProvider {
    suspend fun integrityToken(nonce: String): String
}

/**
 * Dev fallback: emits the `dev-integrity:<nonce>` token the reference wallet-provider backend accepts
 * without real attestation. Use for local development, tests, and the demo's fallback path when a real
 * Play Integrity verdict is unavailable (e.g. a side-loaded debug build). **Never ship this in production.**
 */
class DevIntegrityTokenProvider : IntegrityTokenProvider {
    override suspend fun integrityToken(nonce: String): String = "dev-integrity:$nonce"
}
