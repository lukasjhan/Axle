package com.hopae.eudi.wallet.spi

import java.time.Instant

/**
 * Audit log of wallet transactions — presentations and issuances (ARF transaction logging / GDPR).
 * A cross-cutting port: injected by the host. Production wallets MUST persist these; the default is no-op.
 */
interface TransactionLog {
    suspend fun record(entry: TransactionLogEntry)
    suspend fun list(): List<TransactionLogEntry>
}

class TransactionLogEntry(
    val id: String,
    val type: TransactionType,
    val timestamp: Instant,
    /** The verifier (presentation) or issuer (issuance) — identity, display name, and whether trust was established. */
    val relyingParty: RelyingPartyInfo?,
    val credentialIds: List<String>,
    /** Disclosed claim paths, dot-joined (presentation only). */
    val claimsDisclosed: List<String>,
    val status: TransactionStatus,
)

/** Who the credential was presented to (or issued by), captured for the audit history. */
class RelyingPartyInfo(
    /** Machine identifier: OpenID4VP client_id, mdoc reader id, or issuer URL. */
    val identifier: String,
    /** Human-readable name (e.g. certificate CN), if known. */
    val name: String?,
    /** True only when identity was cryptographically verified to a configured trust anchor. */
    val trusted: Boolean,
    /** Identity scheme (e.g. `x509_san_dns`, `x509_hash`), if applicable. */
    val scheme: String?,
)

enum class TransactionType { Presentation, Issuance }

enum class TransactionStatus { Success, Declined, Failed }

/** Default no-op log. Replace with a persistent adapter for production audit. */
object NoOpTransactionLog : TransactionLog {
    override suspend fun record(entry: TransactionLogEntry) {}
    override suspend fun list(): List<TransactionLogEntry> = emptyList()
}
