package com.hopae.eudi.demo

import android.content.Context
import android.graphics.Bitmap
import androidx.credentials.registry.digitalcredentials.mdoc.MdocEntry
import androidx.credentials.registry.digitalcredentials.mdoc.MdocField
import androidx.credentials.registry.digitalcredentials.openid4vp.OpenId4VpRegistry
import androidx.credentials.registry.digitalcredentials.sdjwt.SdJwtClaim
import androidx.credentials.registry.digitalcredentials.sdjwt.SdJwtEntry
import androidx.credentials.registry.provider.RegistryManager
import androidx.credentials.registry.provider.digitalcredentials.DigitalCredentialEntry
import androidx.credentials.registry.provider.digitalcredentials.EntryDisplayProperties
import androidx.credentials.registry.provider.digitalcredentials.VerificationEntryDisplayProperties
import com.hopae.eudi.wallet.Credential
import com.hopae.eudi.wallet.Lifecycle
import com.hopae.eudi.wallet.Wallet
import com.hopae.eudi.wallet.spi.CredentialFormat

/**
 * Registers the wallet's stored credentials with the Android Credential Manager (Digital Credentials API)
 * as an OpenID4VP holder, so a browser/app can invoke this wallet. The default OpenID4VP matcher is
 * bundled by [OpenId4VpRegistry]; requests are answered by [GetCredentialActivity].
 */
object DcApiRegistrar {
    private const val REGISTRY_ID = "eudi-demo-openid-v1"

    suspend fun register(context: Context, wallet: Wallet) {
        val entries = runCatching { wallet.credentials.list() }.getOrDefault(emptyList()).mapNotNull { entryFor(it) }
        runCatching {
            RegistryManager.create(context).registerCredentials(OpenId4VpRegistry(entries, REGISTRY_ID))
        }.onSuccess { LogStore.log("DC API: registered ${entries.size} credential(s) with Credential Manager") }
            .onFailure { LogStore.log("❌ DC API registration: ${it.javaClass.simpleName}: ${it.message}") }
    }

    private fun entryFor(c: Credential): DigitalCredentialEntry? {
        val issued = c.lifecycle as? Lifecycle.Issued ?: return null
        val display: Set<EntryDisplayProperties> =
            setOf(VerificationEntryDisplayProperties(title(c), c.issuer?.displayName ?: "", icon(), "", ""))
        return when (val f = c.format) {
            is CredentialFormat.SdJwtVc -> SdJwtEntry(
                verifiableCredentialType = f.vct,
                claims = issued.claims.map { SdJwtClaim(it.path, null, emptySet(), true) },
                entryDisplayPropertySet = display,
                id = c.id.value,
            )
            is CredentialFormat.MsoMdoc -> MdocEntry(
                docType = f.docType,
                fields = issued.claims.mapNotNull { claim ->
                    val ns = claim.path.getOrNull(0) ?: return@mapNotNull null
                    val id = claim.path.getOrNull(1) ?: claim.path.last()
                    MdocField(ns, id, null, emptySet())
                },
                entryDisplayPropertySet = display,
                id = c.id.value,
            )
        }
    }

    private fun title(c: Credential): String = when (val f = c.format) {
        is CredentialFormat.SdJwtVc -> f.vct
        is CredentialFormat.MsoMdoc -> f.docType
    }

    private fun icon(): Bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
}
