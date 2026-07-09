package com.hopae.eudi.wallet.vp

import com.hopae.eudi.wallet.cbor.Cbor
import com.hopae.eudi.wallet.cbor.cose.CoseSigner
import com.hopae.eudi.wallet.mdoc.DeviceAuth
import com.hopae.eudi.wallet.mdoc.IssuerSigned
import com.hopae.eudi.wallet.mdoc.MdocDeviceAuth
import com.hopae.eudi.wallet.mdoc.MdocDeviceAuthMode
import com.hopae.eudi.wallet.mdoc.MdocKeyAgreement
import com.hopae.eudi.wallet.mdoc.MdocPresenter
import com.hopae.eudi.wallet.sdjwt.Base64Url
import com.hopae.eudi.wallet.sdjwt.JsonValue
import com.hopae.eudi.wallet.spi.SigningAlgorithm

/**
 * A held mdoc (ISO 18013-5) exposed to DCQL as a [QueryableCredential] and presentable via
 * OpenID4VP. mdoc claims are a two-level tree `{ namespace: { elementIdentifier: value } }`,
 * so a DCQL claim path is `[namespace, element]` (both strings) — see [DcqlEngine] mdoc handling.
 *
 * Device authentication (ISO 18013-5 §9.1.3.5) is a `deviceSignature` by default. When the verifier
 * requests `deviceMac` via `deviceauth_alg_values`, the response is encrypted (so there is a verifier
 * `EReaderKey`), the [deviceKeyAgreement] bridge is present, and [deviceAuth] permits it, this instead
 * produces a `deviceMac` keyed by the DeviceKey/EReaderKey ECDH — see [present].
 */
class HeldMdoc(
    override val credentialId: String,
    val issuerSigned: IssuerSigned,
    private val deviceSigner: CoseSigner? = null,
    private val deviceSignAlgorithm: SigningAlgorithm = SigningAlgorithm.ES256,
    /** ECDH with the mdoc's `DeviceKey`, for `deviceMac`. Null when the DeviceKey cannot key-agree. */
    private val deviceKeyAgreement: MdocKeyAgreement? = null,
    /** Wallet preference when the verifier accepts both forms; `deviceMac` is only used when it can be. */
    private val deviceAuth: MdocDeviceAuthMode = MdocDeviceAuthMode.Signature,
    /** Maps `transaction_data` (§8.4) to a device-signed data element (B.2.1); null = mdoc transaction data unsupported. */
    private val transactionDataBinder: MdocTransactionDataBinder? = null,
) : PresentableCredential {

    override val format: String = "mso_mdoc"
    override val vct: String? = null
    override val docType: String = issuerSigned.parseMso().docType

    override val claims: JsonValue.Obj = JsonValue.Obj(
        issuerSigned.elements().map { (namespace, elements) ->
            namespace to JsonValue.Obj(elements.map { (id, value) -> id to CborJson.toJson(value) })
        }
    )

    /** Builds a base64url `DeviceResponse` disclosing the selected [namespace, element] paths. */
    override suspend fun present(ctx: PresentationContext): String {
        val disclosed = ctx.disclosedPaths.filter { it.size >= 2 }
            .groupBy({ it[0] }, { it[1] })
        // DC API presentations bind the caller origin; the URL/QR flow binds client_id + response_uri.
        val sessionTranscript = if (ctx.origin != null) {
            Oid4vpSessionTranscript.dcApi(ctx.origin, ctx.nonce, ctx.verifierJwkThumbprint)
        } else {
            Oid4vpSessionTranscript.build(ctx.clientId, ctx.responseUri, ctx.nonce, ctx.verifierJwkThumbprint)
        }
        val deviceResponse = MdocPresenter.deviceResponse(
            issuerSigned = issuerSigned,
            docType = docType,
            disclosed = disclosed,
            sessionTranscript = sessionTranscript,
            deviceAuth = selectDeviceAuth(ctx, sessionTranscript),
            deviceSignedNamespaces = bindTransactionData(ctx.transactionData),
        )
        return Base64Url.encode(deviceResponse)
    }

    /**
     * Turns the transaction_data bound to this mdoc (§8.4) into device-signed data elements (B.2.1). The host
     * [transactionDataBinder] supplies the type-specific (namespace, elementId, value); the wallet then rejects
     * (`invalid_transaction_data`) an unsupported type or an element the MSO `keyAuthorizations` did not authorize.
     */
    private fun bindTransactionData(transactionData: List<String>?): Map<String, Map<String, Cbor>> {
        if (transactionData.isNullOrEmpty()) return emptyMap()
        val binder = transactionDataBinder
            ?: throw VpException.InvalidTransactionData("mdoc transaction_data (B.2.1) needs a binder; none is configured")
        val authorizations = issuerSigned.parseMso().keyAuthorizations
        val result = mutableMapOf<String, MutableMap<String, Cbor>>()
        for (raw in transactionData) {
            val element = binder.bind(TransactionData.parse(raw))
                ?: throw VpException.InvalidTransactionData("no mdoc data element defined for this transaction_data type")
            if (authorizations?.authorizes(element.namespace, element.elementId) != true) {
                throw VpException.InvalidTransactionData("data element ${element.namespace}/${element.elementId} is not authorized by the MSO")
            }
            result.getOrPut(element.namespace) { mutableMapOf() }[element.elementId] = element.value
        }
        return result
    }

    /**
     * Picks `deviceSignature` or `deviceMac` (ISO 18013-5 §9.1.3.5). `deviceMac` needs all of: a
     * key-agreement DeviceKey ([deviceKeyAgreement]), a verifier `EReaderKey` on the same curve
     * ([PresentationContext.verifierEncryptionKey], present only for encrypted responses), and the
     * verifier listing our MAC algorithm in `deviceauth_alg_values`. When both forms are acceptable the
     * [deviceAuth] preference decides; when only `deviceMac` is acceptable it is forced (or we fail if
     * it cannot be produced).
     */
    private suspend fun selectDeviceAuth(ctx: PresentationContext, sessionTranscript: Cbor): DeviceAuth {
        val deviceCurve = issuerSigned.parseMso().deviceKey.curve
        val accepts = ctx.deviceAuthAlgValues
        val verifierAcceptsMac = accepts == null || MdocDeviceAuth.macAlgForCurve(deviceCurve) in accepts
        val verifierAcceptsSig = accepts == null || accepts.any { it in signatureAlgIds }
        val encKey = ctx.verifierEncryptionKey

        val canMac = deviceKeyAgreement != null && encKey != null &&
            encKey.curve == deviceCurve && verifierAcceptsMac
        val useMac = when {
            !canMac -> false
            !verifierAcceptsSig -> true                    // verifier accepts only deviceMac → must MAC
            else -> deviceAuth == MdocDeviceAuthMode.Mac   // both acceptable → honor the wallet preference
        }

        if (useMac) {
            val zab = deviceKeyAgreement!!.agree(encKey!!)
            return DeviceAuth.Mac(MdocDeviceAuth.emacKey(zab, sessionTranscript))
        }
        val signer = deviceSigner ?: throw VpException.Unsupported("mdoc presentation requires a device signer")
        if (accepts != null && !verifierAcceptsSig) {
            throw VpException.Unsupported(
                "verifier requires deviceMac (deviceauth_alg_values=$accepts) but this DeviceKey cannot " +
                    "key-agree with the verifier's encryption key"
            )
        }
        return DeviceAuth.Signature(signer, deviceSignAlgorithm)
    }

    // COSE identifiers for the signature the DeviceKey can produce: the RFC 9053 alg and its
    // fully-specified (curve-pinned) variant, either of which the verifier may list.
    private val signatureAlgIds: Set<Long>
        get() = when (deviceSignAlgorithm) {
            SigningAlgorithm.ES256 -> setOf(-7L, -9L)
            SigningAlgorithm.ES384 -> setOf(-35L, -51L)
            SigningAlgorithm.ES512 -> setOf(-36L, -50L)
        }
}
