package com.hopae.eudi.demo

import android.content.Context
import com.google.android.gms.identitycredentials.IdentityCredentialManager
import com.google.android.gms.identitycredentials.RegistrationRequest
import com.hopae.eudi.wallet.Credential
import com.hopae.eudi.wallet.Lifecycle
import com.hopae.eudi.wallet.Wallet
import com.hopae.eudi.wallet.cbor.Cbor
import com.hopae.eudi.wallet.cbor.CborEncoder
import com.hopae.eudi.wallet.spi.CredentialFormat

/**
 * Registers the wallet's credentials with the Credential Manager (Digital Credentials API) using a
 * custom OpenID4VP-1.0-capable WASM matcher (bundled from Multipaz) and the low-level GMS
 * IdentityCredentials API. The androidx `OpenId4VpRegistry` bundles a matcher that does not yet
 * handle the `openid4vp-v1-*` protocols current verifiers use, so we register the matcher ourselves
 * and declare the v1 protocols in the credential database.
 */
object DcApiRegistrar {
    private const val MATCHER_ASSET = "identitycredentialmatcher.wasm"
    private val PROTOCOLS = listOf(
        "openid4vp-v1-signed", "openid4vp-v1-unsigned", "openid4vp-v1-multisigned", "org-iso-mdoc", "openid4vp",
    )

    suspend fun register(context: Context, wallet: Wallet) {
        val creds = runCatching { wallet.credentials.list() }.getOrDefault(emptyList())
        val db = buildDatabase(creds)
        val matcher = runCatching { context.assets.open(MATCHER_ASSET).use { it.readBytes() } }.getOrNull()
        if (matcher == null) { LogStore.log("❌ DC API: matcher wasm missing"); return }
        val client = IdentityCredentialManager.getClient(context)
        // Two registrations: the androidx digital-credential type + the legacy Credman type.
        listOf("androidx.credentials.TYPE_DIGITAL_CREDENTIAL", "com.credman.IdentityCredential").forEach { type ->
            client.registerCredentials(
                RegistrationRequest(credentials = db, matcher = matcher, type = type, requestType = "", protocolTypes = emptyList()),
            )
                .addOnSuccessListener { if (type.startsWith("androidx")) LogStore.log("DC API: registered ${creds.size} credential(s) [$PROTOCOLS]") }
                .addOnFailureListener { LogStore.log("❌ DC API register ($type): ${it.message}") }
        }
    }

    // ---- Credential database CBOR (matcher format) ----

    private fun txt(s: String) = Cbor.Text(s)
    private fun map(entries: List<Pair<String, Cbor>>) = Cbor.CborMap(entries.map { txt(it.first) to it.second })
    private fun field(displayName: String, value: String) =
        Cbor.Array(listOf(txt(displayName), txt(value), txt(if (value.length < 128) value else "")))

    private fun buildDatabase(creds: List<Credential>): ByteArray {
        val entries = creds.mapNotNull { credentialEntry(it) }
        val db = map(
            listOf(
                "protocols" to Cbor.Array(PROTOCOLS.map { txt(it) }),
                "credentials" to Cbor.Array(entries),
            ),
        )
        return CborEncoder.encode(db)
    }

    private fun credentialEntry(c: Credential): Cbor? {
        val issued = c.lifecycle as? Lifecycle.Issued ?: return null
        val common = listOf(
            "title" to txt(title(c)),
            "subtitle" to txt(c.issuer?.displayName ?: ""),
            "bitmap" to Cbor.Bytes(ByteArray(0)),
        )
        return when (val f = c.format) {
            is CredentialFormat.MsoMdoc -> {
                val namespaces = issued.claims.filter { it.path.size >= 2 }.groupBy { it.path[0] }.map { (ns, claims) ->
                    ns to map(claims.distinctBy { it.path[1] }.map { it.path[1] to field(it.path[1], it.value.display()) })
                }
                map(common + ("mdoc" to map(listOf(
                    "documentId" to txt(c.id.value),
                    "docType" to txt(f.docType),
                    "namespaces" to map(namespaces),
                ))))
            }
            is CredentialFormat.SdJwtVc -> {
                val claims = issued.claims.map { claim ->
                    val name = claim.path.joinToString(".")
                    name to field(name, claim.value.display())
                }
                map(common + ("sdjwt" to map(listOf(
                    "documentId" to txt(c.id.value),
                    "vct" to txt(f.vct),
                    "claims" to map(claims),
                ))))
            }
        }
    }

    private fun title(c: Credential): String = when (val f = c.format) {
        is CredentialFormat.SdJwtVc -> f.vct
        is CredentialFormat.MsoMdoc -> f.docType
    }
}
