package com.hopae.eudi.wallet

import com.hopae.eudi.wallet.spi.CredentialFormat
import com.hopae.eudi.wallet.spi.CredentialId
import com.hopae.eudi.wallet.spi.KeyUse
import java.time.Instant

/**
 * Format-agnostic credential view, assembled from the storage envelope.
 * Issuer/display metadata is captured at issuance; claims/validity are parsed from the payload.
 */
class Credential(
    val id: CredentialId,
    val format: CredentialFormat,
    val lifecycle: Lifecycle,
    val issuer: IssuerInfo?,
    val display: CredentialDisplay?,
    val configurationId: String?,
    val createdAt: Instant,
)

/**
 * Where the credential came from (captured from issuer metadata at issuance).
 * [trusted]: the credential's issuer signature (DSC) chained to a trusted issuer anchor — true/false/null(unchecked).
 * [registered]: the issuer's `.well-known` signed metadata chained to a trusted issuer anchor (a registered issuer).
 */
data class IssuerInfo(
    val url: String,
    val displayName: String? = null,
    val trusted: Boolean? = null,
    val registered: Boolean? = null,
)

/** Display metadata for a credential type (issuer-metadata derived). */
data class CredentialDisplay(val name: String? = null, val logoUri: String? = null, val backgroundColor: String? = null)

sealed interface Lifecycle {
    data class Issued(val claims: List<Claim>, val validity: ValidityInfo?, val instances: CredentialInstances) : Lifecycle
    data class Deferred(val retryAfter: Instant?) : Lifecycle
    data class Pending(val authorizationUrl: String?) : Lifecycle
}

/** A disclosed claim, path-addressed (namespace+element for mdoc, JSON path for SD-JWT VC). */
data class Claim(val path: List<String>, val value: ClaimValue, val category: ClaimCategory = ClaimCategory.Subject)

/**
 * Whether a claim carries the subject's personal data or the credential's administrative metadata. Derived
 * structurally where possible (SD-JWT VC registered claims like iss/iat/exp/vct/cnf/status) and from the
 * ARF/ISO administrative element names otherwise (issuing_authority/country, issuance/expiry dates, …). A
 * hint for grouping — consumers may present it however they like.
 */
enum class ClaimCategory { Subject, Metadata }

/** The value's underlying shape, so a UI can render it without re-sniffing the raw type. */
enum class ClaimValueKind { Text, Number, Boolean, Date, Array, Unknown }

/** A claim value with a format-agnostic rendering and a [kind] hint. */
class ClaimValue internal constructor(val raw: Any?, val kind: ClaimValueKind = ClaimValueKind.Text) {
    fun display(): String = when (kind) {
        ClaimValueKind.Boolean -> if (raw == true) "Yes" else "No"
        ClaimValueKind.Array -> (raw as? List<*>)?.joinToString(", ") { it?.toString().orEmpty() } ?: (raw?.toString() ?: "")
        else -> raw?.toString() ?: ""
    }
    override fun toString(): String = display()
}

data class ValidityInfo(val validFrom: Instant?, val validUntil: Instant?)

/** Batch instance accounting (HAIP one-time-use / rotate). */
data class CredentialInstances(val remaining: Int, val use: KeyUse)
