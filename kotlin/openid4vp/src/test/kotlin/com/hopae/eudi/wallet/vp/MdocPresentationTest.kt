package com.hopae.eudi.wallet.vp

import com.hopae.eudi.wallet.cbor.Cbor
import com.hopae.eudi.wallet.cbor.CborDecoder
import com.hopae.eudi.wallet.cbor.CborEncoder
import com.hopae.eudi.wallet.cbor.cose.CoseSign1
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
import kotlin.test.assertTrue

class MdocPresentationTest {

    private val docType = "org.iso.18013.5.1.mDL"
    private val namespace = "org.iso.18013.5.1"

    private val ctx = PresentationContext(
        disclosedPaths = listOf(listOf("org.iso.18013.5.1", "family_name"), listOf("org.iso.18013.5.1", "given_name")),
        clientId = "x509_hash:abc", nonce = "nonce-123", responseUri = "https://verifier.example/response",
        issuedAt = 1_700_000_000, transactionData = null, verifierJwkThumbprint = null,
    )

    private fun map(c: Cbor, key: String): Cbor? =
        (c as Cbor.CborMap).entries.firstOrNull { (k, _) -> (k as? Cbor.Text)?.value == key }?.second

    @Test
    fun presentsDeviceResponseWithSelectiveDisclosureAndDeviceSignature() = runBlocking {
        val area = SoftwareSecureArea()
        val issuerKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val deviceKey: KeyInfo = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val bytes = MdocTestIssuer.issue(
            area = area, issuerKey = issuerKey, deviceKey = deviceKey.publicKey,
            docType = docType, namespace = namespace,
            elements = listOf("family_name" to Cbor.Text("Han"), "given_name" to Cbor.Text("Jongho"), "age_over_18" to Cbor.Bool(true)),
            x5chain = listOf(byteArrayOf(0x30, 0x01)),
            signed = Instant.parse("2026-01-01T00:00:00Z"), validFrom = Instant.parse("2026-01-01T00:00:00Z"),
            validUntil = Instant.parse("2027-01-01T00:00:00Z"),
        )
        val held = HeldMdoc("mdl-1", IssuerSigned.decode(bytes), SecureAreaCoseSigner(area, deviceKey.handle, SigningAlgorithm.ES256))

        val deviceResponseB64 = held.present(ctx)
        val deviceResponse = CborDecoder.decode(Base64Url.decode(deviceResponseB64))

        assertEquals(Cbor.Text("1.0"), map(deviceResponse, "version"))
        val document = (map(deviceResponse, "documents") as Cbor.Array).items.single()
        assertEquals(Cbor.Text(docType), map(document, "docType"))

        // selective disclosure: only family_name + given_name present, age_over_18 withheld
        val presentedIssuerSigned = IssuerSigned.fromCbor(map(document, "issuerSigned")!!)
        val disclosedIds = presentedIssuerSigned.nameSpaces[namespace]!!.map { it.item.elementIdentifier }.toSet()
        assertEquals(setOf("family_name", "given_name"), disclosedIds)

        // device signature verifies over the reconstructed DeviceAuthenticationBytes
        val deviceSigned = map(document, "deviceSigned")!!
        val deviceSignature = CoseSign1.fromCbor(map(map(deviceSigned, "deviceAuth")!!, "deviceSignature")!!)
        val deviceAuthBytes = reconstructDeviceAuthBytes()
        assertTrue(deviceSignature.verify(deviceKey.publicKey, detachedPayload = deviceAuthBytes), "device signature must verify")
    }

    private fun reconstructDeviceAuthBytes(): ByteArray {
        val sessionTranscript = Oid4vpSessionTranscript.build(ctx.clientId, ctx.responseUri, ctx.nonce, ctx.verifierJwkThumbprint)
        val deviceNameSpacesBytes = Cbor.Tagged(24u, Cbor.Bytes(CborEncoder.encode(Cbor.CborMap(emptyList()))))
        val deviceAuth = Cbor.Array(listOf(Cbor.Text("DeviceAuthentication"), sessionTranscript, Cbor.Text(docType), deviceNameSpacesBytes))
        return CborEncoder.encode(Cbor.Tagged(24u, Cbor.Bytes(CborEncoder.encode(deviceAuth))))
    }
}
