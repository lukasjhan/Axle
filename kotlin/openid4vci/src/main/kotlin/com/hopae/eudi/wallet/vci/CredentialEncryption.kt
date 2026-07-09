package com.hopae.eudi.wallet.vci

import com.hopae.eudi.wallet.sdjwt.JsonValue
import com.hopae.eudi.wallet.sdjwt.Jwe
import com.hopae.eudi.wallet.sdjwt.JweEnc
import com.hopae.eudi.wallet.sdjwt.JweRecipientKey
import com.hopae.eudi.wallet.sdjwt.JwkEc

/** How the wallet treats encrypted Credential Requests and Responses (OpenID4VCI §8.2, §10). */
enum class CredentialEncryption {
    /** Encrypt only when the issuer sets `encryption_required` (default; keeps plaintext otherwise). */
    WhenRequired,

    /** Encrypt whenever the issuer advertises `credential_response_encryption`. */
    Preferred,

    /** Always encrypt; fail when the issuer does not advertise support. */
    Required,
}

/** The ECDH-ES `alg` this SDK implements; §10 requires the JWE `alg` to equal the chosen JWK's `alg`. */
private const val ECDH_ES = "ECDH-ES"

/** The content-encryption algorithms we can negotiate, most preferred first. */
private val SUPPORTED_ENC = listOf(JweEnc.A256GCM, JweEnc.A128GCM, JweEnc.A192GCM)

/**
 * A negotiated encryption context for one Credential Request/Response pair (§10). Both directions are
 * used together: §8.2 requires the request to be encrypted whenever a `credential_response_encryption`
 * object is sent, so an attacker cannot substitute the wallet's response-encryption key.
 */
class CredentialEncryptionSession internal constructor(
    private val issuerKey: com.hopae.eudi.wallet.cbor.cose.EcPublicKey,
    private val issuerKid: String?,
    private val requestEnc: JweEnc,
    private val responseEnc: JweEnc,
    private val recipient: JweRecipientKey,
) {
    /** The `credential_response_encryption` object to embed in the Credential Request. */
    fun requestObject(): JsonValue.Obj = JsonValue.Obj(
        listOf(
            "jwk" to recipient.publicJwk(ECDH_ES),
            "enc" to JsonValue.Str(responseEnc.id),
        )
    )

    /** Encrypts the Credential Request JSON to the issuer's key; the body becomes a compact JWE. */
    fun encryptRequest(json: String): String =
        Jwe.encryptEcdhEs(json.encodeToByteArray(), issuerKey, requestEnc, kid = issuerKid)

    fun decryptResponse(compact: String): JsonValue.Obj {
        val plaintext = runCatching { recipient.decrypt(compact.trim()) }.getOrElse {
            throw VciException.ProtocolError("credential response JWE did not decrypt: ${it.message}")
        }
        return JsonValue.parse(plaintext.decodeToString()) as? JsonValue.Obj
            ?: throw VciException.ProtocolError("encrypted credential response is not a JSON object")
    }

    companion object {
        /**
         * Resolves [policy] against the issuer's metadata, returning null when the exchange stays plaintext.
         * Throws when encryption is called for but the issuer cannot support the parts we need.
         */
        internal fun negotiate(policy: CredentialEncryption, meta: CredentialIssuerMetadata): CredentialEncryptionSession? {
            val responseMeta = meta.credentialResponseEncryption
            val required = responseMeta?.encryptionRequired == true || policy == CredentialEncryption.Required
            val wanted = required || (policy == CredentialEncryption.Preferred && responseMeta != null)
            if (!wanted) return null

            responseMeta ?: throw VciException.MetadataError("issuer advertises no credential_response_encryption")
            if (responseMeta.algValuesSupported.isNotEmpty() && ECDH_ES !in responseMeta.algValuesSupported) {
                throw VciException.Unsupported("issuer response encryption needs one of ${responseMeta.algValuesSupported}; only $ECDH_ES is implemented")
            }
            // §8.2: "Credential Request encryption MUST be used if the credential_response_encryption
            // parameter is included, to prevent it being substituted by an attacker."
            val requestMeta = meta.credentialRequestEncryption
                ?: throw VciException.MetadataError("credential_response_encryption requires credential_request_encryption (§8.2)")

            val jwk = requestMeta.jwks.firstOrNull { (it["alg"] as? JsonValue.Str)?.value == ECDH_ES }
                ?: throw VciException.Unsupported("no $ECDH_ES key in credential_request_encryption.jwks")
            val issuerKey = JwkEc.fromJson(jwk) ?: throw VciException.MetadataError("credential_request_encryption jwk is not an EC key")

            return CredentialEncryptionSession(
                issuerKey = issuerKey,
                // §10: when the chosen JWK carries a kid, the JWE header MUST repeat it.
                issuerKid = (jwk["kid"] as? JsonValue.Str)?.value,
                requestEnc = pickEnc(requestMeta.encValuesSupported, "credential_request_encryption"),
                responseEnc = pickEnc(responseMeta.encValuesSupported, "credential_response_encryption"),
                recipient = JweRecipientKey.generate(),
            )
        }

        /** First mutually supported `enc`; an empty issuer list means "unconstrained". */
        private fun pickEnc(issuerSupported: List<String>, where: String): JweEnc {
            if (issuerSupported.isEmpty()) return JweEnc.A128GCM
            return SUPPORTED_ENC.firstOrNull { it.id in issuerSupported }
                ?: throw VciException.Unsupported("$where offers $issuerSupported; this SDK implements ${SUPPORTED_ENC.map { it.id }}")
        }
    }
}
