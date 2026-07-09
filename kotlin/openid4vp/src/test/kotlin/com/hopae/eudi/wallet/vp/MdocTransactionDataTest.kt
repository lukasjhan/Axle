package com.hopae.eudi.wallet.vp

import com.hopae.eudi.wallet.cbor.Cbor
import com.hopae.eudi.wallet.cbor.CborDecoder
import com.hopae.eudi.wallet.mdoc.IssuerSigned
import com.hopae.eudi.wallet.mdoc.MdocTestIssuer
import com.hopae.eudi.wallet.sdjwt.Base64Url
import com.hopae.eudi.wallet.spi.KeyInfo
import com.hopae.eudi.wallet.spi.KeySpec
import com.hopae.eudi.wallet.spi.SecureAreaCoseSigner
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.testkit.SoftwareSecureArea
import kotlinx.coroutines.runBlocking
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/**
 * OpenID4VP mdoc transaction_data (ISO 18013-7 B.2.1): a host-supplied binder turns a transaction_data entry
 * into a device-signed data element, which the wallet device-signs only after checking the MSO
 * `keyAuthorizations` (§9.1.2.4) authorized it.
 */
class MdocTransactionDataTest {

    private val docType = "org.iso.18013.5.1.mDL"
    private val namespace = "org.iso.18013.5.1"

    private fun mdoc(area: SoftwareSecureArea, issuerKey: KeyInfo, deviceKey: com.hopae.eudi.wallet.cbor.cose.EcPublicKey,
                     authorized: Map<String, List<String>>?): IssuerSigned = runBlocking {
        IssuerSigned.decode(
            MdocTestIssuer.issue(
                area = area, issuerKey = issuerKey, deviceKey = deviceKey, docType = docType, namespace = namespace,
                elements = listOf("family_name" to Cbor.Text("Han")),
                x5chain = listOf(byteArrayOf(0x30, 0x01)),
                signed = Instant.parse("2026-01-01T00:00:00Z"),
                validFrom = Instant.parse("2026-01-01T00:00:00Z"),
                validUntil = Instant.parse("2027-01-01T00:00:00Z"),
                authorizedElements = authorized,
            )
        )
    }

    private fun held(area: SoftwareSecureArea, issuerSigned: IssuerSigned, deviceKey: KeyInfo,
                     binder: MdocTransactionDataBinder?): HeldMdoc = HeldMdoc(
        "mdl", issuerSigned, SecureAreaCoseSigner(area, deviceKey.handle, SigningAlgorithm.ES256),
        transactionDataBinder = binder,
    )

    private fun ctx(rawTx: String) = PresentationContext(
        disclosedPaths = listOf(listOf(namespace, "family_name")),
        clientId = "verifier", nonce = "n", responseUri = "https://v.example/cb",
        issuedAt = 1_700_000_000, transactionData = listOf(rawTx), verifierJwkThumbprint = null,
    )

    private fun tx(type: String) = Base64Url.encode("""{"type":"$type","credential_ids":["mdl"]}""".encodeToByteArray())

    /** Binds a "payment" transaction to the device-signed element [ns]/[id]. */
    private fun binder(ns: String, id: String) = MdocTransactionDataBinder { td ->
        if (td.type == "payment") DeviceSignedTransactionData(ns, id, Cbor.Text("authorized")) else null
    }

    private fun deviceSignedElement(presentation: String, ns: String, id: String): Cbor? {
        fun map(c: Cbor, key: String) = (c as Cbor.CborMap).entries.firstOrNull { (k, _) -> (k as? Cbor.Text)?.value == key }?.second
        val doc = (map(CborDecoder.decode(Base64Url.decode(presentation)), "documents") as Cbor.Array).items.single()
        val nsBytes = (map(map(doc, "deviceSigned")!!, "nameSpaces") as Cbor.Tagged).value as Cbor.Bytes
        val nsMap = CborDecoder.decode(nsBytes.value)
        return (map(nsMap, ns) as? Cbor.CborMap)?.let { map(it, id) }
    }

    @Test
    fun bindsAuthorizedTransactionDataAsDeviceSignedElement() = runBlocking {
        val area = SoftwareSecureArea()
        val issuerKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val deviceKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val issuerSigned = mdoc(area, issuerKey, deviceKey.publicKey, authorized = mapOf(namespace to listOf("tx_auth")))

        val presentation = held(area, issuerSigned, deviceKey, binder(namespace, "tx_auth")).present(ctx(tx("payment")))

        assertEquals(Cbor.Text("authorized"), deviceSignedElement(presentation, namespace, "tx_auth"),
            "the authorized transaction_data element is device-signed into the response")
    }

    @Test
    fun rejectsElementNotAuthorizedByMso(): Unit = runBlocking {
        val area = SoftwareSecureArea()
        val issuerKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val deviceKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        // MSO authorizes tx_auth, but the binder returns tx_other → unauthorized.
        val issuerSigned = mdoc(area, issuerKey, deviceKey.publicKey, authorized = mapOf(namespace to listOf("tx_auth")))

        assertFailsWith<VpException.InvalidTransactionData> {
            held(area, issuerSigned, deviceKey, binder(namespace, "tx_other")).present(ctx(tx("payment")))
        }
    }

    @Test
    fun rejectsUnsupportedTypeAndMissingBinder(): Unit = runBlocking {
        val area = SoftwareSecureArea()
        val issuerKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val deviceKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val issuerSigned = mdoc(area, issuerKey, deviceKey.publicKey, authorized = mapOf(namespace to listOf("tx_auth")))

        // binder returns null for an unknown type
        assertFailsWith<VpException.InvalidTransactionData> {
            held(area, issuerSigned, deviceKey, binder(namespace, "tx_auth")).present(ctx(tx("unknown_type")))
        }
        // no binder configured at all
        assertFailsWith<VpException.InvalidTransactionData> {
            held(area, issuerSigned, deviceKey, binder = null).present(ctx(tx("payment")))
        }
    }
}
