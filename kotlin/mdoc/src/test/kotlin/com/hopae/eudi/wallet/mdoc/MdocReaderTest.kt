package com.hopae.eudi.wallet.mdoc

import com.hopae.eudi.wallet.cbor.Cbor
import com.hopae.eudi.wallet.cbor.cose.EcPublicKey
import com.hopae.eudi.wallet.spi.KeySpec
import com.hopae.eudi.wallet.spi.SecureAreaCoseSigner
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.testkit.SoftwareSecureArea
import kotlinx.coroutines.runBlocking
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/** The dual-role loop: reader builds a DeviceRequest, wallet responds, reader verifies the response. */
class MdocReaderTest {

    private val docType = "org.iso.18013.5.1.mDL"
    private val namespace = "org.iso.18013.5.1"
    private val readerX5c = listOf(byteArrayOf(0x30, 0x01))

    private class Party {
        val area = SoftwareSecureArea()
        val reader = runBlocking { area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256)) }
        val issuer = runBlocking { area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256)) }
        val device = runBlocking { area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256)) }
    }

    private fun issuerTrust(key: EcPublicKey) = MdocIssuerTrust { key }

    private fun mdoc(p: Party): ByteArray = runBlocking {
        MdocTestIssuer.issue(
            area = p.area, issuerKey = p.issuer, deviceKey = p.device.publicKey, docType = docType, namespace = namespace,
            elements = listOf("family_name" to Cbor.Text("Han"), "given_name" to Cbor.Text("Jongho"), "age_over_18" to Cbor.Bool(true)),
            x5chain = listOf(byteArrayOf(0x30, 0x02)),
            signed = Instant.parse("2026-01-01T00:00:00Z"), validFrom = Instant.parse("2026-01-01T00:00:00Z"), validUntil = Instant.parse("2027-01-01T00:00:00Z"),
        )
    }

    private fun readerFacade(p: Party) = MdocReader(
        readerAuth = ReaderAuthSigner(SecureAreaCoseSigner(p.area, p.reader.handle, SigningAlgorithm.ES256), readerX5c),
        issuerTrust = issuerTrust(p.issuer.publicKey),
        now = { Instant.parse("2026-06-01T00:00:00Z") },
    )

    @Test
    fun readerWalletRoundTrip() = runBlocking {
        val p = Party()
        val issuerSigned = IssuerSigned.decode(mdoc(p))
        val st = MdocSessionTranscript.dcApiIsoMdoc("ZW5j", "https://reader.example")
        val reader = readerFacade(p)

        // 1. reader builds the DeviceRequest
        val deviceRequest = reader.buildDeviceRequest(
            listOf(RequestedDocument(docType, mapOf(namespace to listOf("family_name", "given_name")))), st,
        )

        // 2. wallet parses, authenticates the reader, discloses, builds the DeviceResponse
        val docReq = DeviceRequest.decode(deviceRequest).docRequestFor(docType)!!
        assertTrue(ReaderAuth.verify(docReq, st, MdocReaderTrust { p.reader.publicKey }).trusted)
        val deviceResponse = MdocPresenter.deviceResponse(
            issuerSigned = issuerSigned, docType = docType, disclosed = docReq.disclosable(issuerSigned),
            sessionTranscript = st, deviceSigner = SecureAreaCoseSigner(p.area, p.device.handle, SigningAlgorithm.ES256),
        )

        // 3. reader verifies the DeviceResponse (issuer trust + holder binding)
        val verified = reader.verifyDeviceResponse(deviceResponse, st).single()
        assertEquals(docType, verified.docType)
        assertTrue(verified.deviceAuthenticated)
        assertEquals(Cbor.Text("Han"), verified.elements[namespace]!!["family_name"])
        assertEquals(Cbor.Text("Jongho"), verified.elements[namespace]!!["given_name"])
        assertTrue(verified.elements[namespace]!!["age_over_18"] == null) // not disclosed
    }

    @Test
    fun deviceResponseFromWrongSessionRejected(): Unit = runBlocking {
        val p = Party()
        val issuerSigned = IssuerSigned.decode(mdoc(p))
        val st = MdocSessionTranscript.dcApiIsoMdoc("ZW5j", "https://reader.example")
        val deviceResponse = MdocPresenter.deviceResponse(
            issuerSigned = issuerSigned, docType = docType, disclosed = mapOf(namespace to listOf("family_name")),
            sessionTranscript = st, deviceSigner = SecureAreaCoseSigner(p.area, p.device.handle, SigningAlgorithm.ES256),
        )
        // reader verifies against a DIFFERENT session -> deviceSignature (holder binding) fails
        val otherSt = MdocSessionTranscript.dcApiIsoMdoc("ZW5j", "https://evil.example")
        assertFailsWith<MdocException> { readerFacade(p).verifyDeviceResponse(deviceResponse, otherSt) }
    }

    @Test
    fun untrustedIssuerRejected(): Unit = runBlocking {
        val p = Party()
        val rogue = p.area.createKey(KeySpec(secureArea = p.area.id, algorithm = SigningAlgorithm.ES256))
        val issuerSigned = IssuerSigned.decode(mdoc(p))
        val st = MdocSessionTranscript.dcApiIsoMdoc("ZW5j", "https://reader.example")
        val deviceResponse = MdocPresenter.deviceResponse(
            issuerSigned = issuerSigned, docType = docType, disclosed = mapOf(namespace to listOf("family_name")),
            sessionTranscript = st, deviceSigner = SecureAreaCoseSigner(p.area, p.device.handle, SigningAlgorithm.ES256),
        )
        val reader = MdocReader(issuerTrust = issuerTrust(rogue.publicKey), now = { Instant.parse("2026-06-01T00:00:00Z") })
        assertFailsWith<MdocException> { reader.verifyDeviceResponse(deviceResponse, st) }
    }
}
