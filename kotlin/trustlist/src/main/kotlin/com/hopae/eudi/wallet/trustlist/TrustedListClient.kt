package com.hopae.eudi.wallet.trustlist

import com.hopae.eudi.wallet.cbor.cose.Ecdsa
import com.hopae.eudi.wallet.sdjwt.Base64Url
import com.hopae.eudi.wallet.sdjwt.JsonValue
import com.hopae.eudi.wallet.spi.HttpMethod
import com.hopae.eudi.wallet.spi.HttpRequest
import com.hopae.eudi.wallet.spi.HttpTransport
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.spi.coseAlgorithm
import com.hopae.eudi.wallet.trust.X509Support
import java.util.Base64

class TrustListException(message: String) : Exception(message)

/**
 * Fetches an ETSI TS 119 602 Trusted List (JAdES-signed, as published by the Scheme Operator) from a URL,
 * verifies the Scheme Operator's signature against a pinned anchor, and returns the listed service CA
 * certificates as DER — ready to feed into `TrustConfig` (issuer / reader / registrar anchors).
 *
 * Deliberately standalone: the core trust validators stay DER-based and never depend on it, so a host that
 * does not use a Trusted List can keep supplying DER directly. The list carries a JAdES B-B signature
 * (`crit` present), so the signature is verified directly (as `WRPRCVerifier` does), not via `Jws.verify`.
 */
class TrustedListClient(private val http: HttpTransport) {

    /**
     * @param url the JAdES-signed list, e.g. `https://…/tl/registrar.jades.json`.
     * @param schemeOperatorAnchorDer the pinned Scheme Operator signing certificate (DER); the list
     *   signature is verified against its key.
     * @return the DER of each listed service certificate (the CA anchors).
     */
    suspend fun fetchCACerts(url: String, schemeOperatorAnchorDer: ByteArray): List<ByteArray> {
        val resp = http.execute(HttpRequest(HttpMethod.GET, url, listOf("Accept" to "application/json")))
        if (resp.status !in 200..299) throw TrustListException("trusted list fetch failed: HTTP ${resp.status}")
        return verifyAndExtract(resp.body, schemeOperatorAnchorDer)
    }

    /** Verifies an already-fetched flattened-JWS list body and extracts the CA DERs (exposed for offline use/tests). */
    fun verifyAndExtract(body: ByteArray, schemeOperatorAnchorDer: ByteArray): List<ByteArray> {
        val envelope = JsonValue.parse(body.decodeToString()) as? JsonValue.Obj
            ?: throw TrustListException("trusted list is not JSON")
        val protectedB64 = (envelope["protected"] as? JsonValue.Str)?.value
        val payloadB64 = (envelope["payload"] as? JsonValue.Str)?.value
        val signatureB64 = (envelope["signature"] as? JsonValue.Str)?.value
        if (protectedB64 == null || payloadB64 == null || signatureB64 == null) {
            throw TrustListException("trusted list is not a flattened JWS { protected, payload, signature }")
        }

        // --- Scheme Operator signature (JAdES B-B) — verify directly against the pinned anchor's key. ---
        val header = JsonValue.parse(Base64Url.decode(protectedB64).decodeToString()) as? JsonValue.Obj
            ?: throw TrustListException("invalid protected header")
        if ((header["alg"] as? JsonValue.Str)?.value != "ES256") throw TrustListException("trusted list alg must be ES256")

        val key = X509Support.ecPublicKey(X509Support.parse(schemeOperatorAnchorDer))
        val signingInput = "$protectedB64.$payloadB64".encodeToByteArray()
        val signature = Base64Url.decode(signatureB64)
        if (!Ecdsa.verify(key, SigningAlgorithm.ES256.coseAlgorithm, signingInput, signature)) {
            throw TrustListException("trusted list signature does not verify against the Scheme Operator anchor")
        }

        // --- Extract the listed service certificates (base64 DER, per TS 119 602). ---
        val payload = JsonValue.parse(Base64Url.decode(payloadB64).decodeToString()) as? JsonValue.Obj
            ?: throw TrustListException("invalid payload")
        val cas = mutableListOf<ByteArray>()
        (payload["trustedEntitiesList"] as? JsonValue.Arr)?.items?.forEach { entity ->
            ((entity as? JsonValue.Obj)?.get("trustedEntityServices") as? JsonValue.Arr)?.items?.forEach { service ->
                val certB64 =
                    (((service as? JsonValue.Obj)?.get("serviceDigitalIdentity") as? JsonValue.Obj)?.get("x509Certificate") as? JsonValue.Str)?.value
                if (certB64 != null) cas.add(Base64.getDecoder().decode(certB64))
            }
        }
        if (cas.isEmpty()) throw TrustListException("trusted list has no service certificates")
        return cas
    }
}
