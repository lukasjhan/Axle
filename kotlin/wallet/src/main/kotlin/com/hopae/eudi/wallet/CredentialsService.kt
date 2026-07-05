package com.hopae.eudi.wallet

import com.hopae.eudi.wallet.spi.CredentialId
import com.hopae.eudi.wallet.store.CredentialEnvelope
import com.hopae.eudi.wallet.store.CredentialStore
import com.hopae.eudi.wallet.store.CredentialStoreChange
import com.hopae.eudi.wallet.store.EnvelopeLifecycle
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Stored-credential management (API-CONTRACT.md §6.5). Reads are local; `status` hits the network. */
class CredentialsService internal constructor(private val store: CredentialStore) {

    suspend fun list(filter: CredentialFilter = CredentialFilter.All): List<Credential> =
        store.list().map { it.toCredential() }.filter { filter.matches(it) }

    suspend fun get(id: CredentialId): Credential? = store.get(id)?.toCredential()

    suspend fun delete(id: CredentialId) = store.delete(id)

    /** Reactive list changes (Added/Updated/Removed) for UI refresh. */
    val changes: Flow<CredentialChange> = store.changes.map { it.toCredentialChange() }
}

sealed interface CredentialChange {
    val id: CredentialId

    data class Added(override val id: CredentialId) : CredentialChange
    data class Updated(override val id: CredentialId) : CredentialChange
    data class Removed(override val id: CredentialId) : CredentialChange
}

internal fun CredentialStoreChange.toCredentialChange(): CredentialChange = when (this) {
    is CredentialStoreChange.Added -> CredentialChange.Added(id)
    is CredentialStoreChange.Updated -> CredentialChange.Updated(id)
    is CredentialStoreChange.Removed -> CredentialChange.Removed(id)
}

/** Assembles the format-agnostic [Credential] view from a storage envelope. */
internal fun CredentialEnvelope.toCredential(): Credential = Credential(
    id = id,
    format = format,
    createdAt = createdAt,
    issuer = null, // captured at issuance — metadata slice
    display = null,
    configurationId = null,
    lifecycle = when (val lc = lifecycle) {
        is EnvelopeLifecycle.Issued -> Lifecycle.Issued(
            claims = emptyList(), // parsed from payload — claims slice
            validity = null,
            instances = CredentialInstances(remaining = lc.instances.size, use = lc.policy.use),
        )
        is EnvelopeLifecycle.Deferred -> Lifecycle.Deferred(lc.retryAfter)
        is EnvelopeLifecycle.Pending -> Lifecycle.Pending(lc.authorizationUrl)
    },
)
