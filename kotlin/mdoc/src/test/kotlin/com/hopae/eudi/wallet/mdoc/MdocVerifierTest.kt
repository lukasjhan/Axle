package com.hopae.eudi.wallet.mdoc

import com.hopae.eudi.wallet.cbor.Cbor
import com.hopae.eudi.wallet.cbor.cose.EcPublicKey
import com.hopae.eudi.wallet.spi.KeySpec
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.testkit.SoftwareSecureArea
import kotlinx.coroutines.runBlocking
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class MdocVerifierTest {

    private val docType = "org.iso.18013.5.1.mDL"
    private val namespace = "org.iso.18013.5.1"
    private val now = Instant.parse("2026-01-01T00:00:00Z")

    private class TestTrust(val expected: EcPublicKey) : MdocIssuerTrust {
        // Unit-level: return the known issuer key (chain validation is covered by the trust module).
        override suspend fun issuerKey(x5chain: List<ByteArray>): EcPublicKey = expected
    }

    private fun issued(area: SoftwareSecureArea, issuerKey: com.hopae.eudi.wallet.spi.KeyInfo, deviceKey: EcPublicKey,
                       validUntil: Instant = Instant.parse("2027-01-01T00:00:00Z")): ByteArray = runBlocking {
        MdocTestIssuer.issue(
            area = area, issuerKey = issuerKey, deviceKey = deviceKey,
            docType = docType, namespace = namespace,
            elements = listOf(
                "family_name" to Cbor.Text("Han"),
                "given_name" to Cbor.Text("Jongho"),
                "age_over_18" to Cbor.Bool(true),
            ),
            x5chain = listOf(byteArrayOf(0x30, 0x01, 0x02)), // placeholder DER; resolver returns the known key
            signed = Instant.parse("2026-01-01T00:00:00Z"),
            validFrom = Instant.parse("2026-01-01T00:00:00Z"),
            validUntil = validUntil,
        )
    }

    @Test
    fun parseRoundtrip() {
        val area = SoftwareSecureArea()
        val issuerKey = runBlocking { area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256)) }
        val deviceKey = runBlocking { area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256)) }.publicKey
        val bytes = issued(area, issuerKey, deviceKey)

        val parsed = IssuerSigned.decode(bytes)
        assertEquals(3, parsed.nameSpaces[namespace]!!.size)
        assertEquals("family_name", parsed.nameSpaces[namespace]!![0].item.elementIdentifier)
        assertContentEquals(byteArrayOf(0x30, 0x01, 0x02), parsed.issuerCertChain!!.first())
    }

    @Test
    fun verifiesAndDisclosesElements() = runBlocking {
        val area = SoftwareSecureArea()
        val issuerKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val deviceKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256)).publicKey
        val bytes = issued(area, issuerKey, deviceKey)

        val verified = MdocVerifier(TestTrust(issuerKey.publicKey), now = { now }).verify(IssuerSigned.decode(bytes))
        assertEquals(docType, verified.docType)
        assertEquals(Cbor.Text("Han"), verified.elements[namespace]!!["family_name"])
        assertEquals(Cbor.Text("Jongho"), verified.elements[namespace]!!["given_name"])
        assertEquals(Cbor.Bool(true), verified.elements[namespace]!!["age_over_18"])
        assertContentEquals(deviceKey.x, verified.deviceKey.x) // holder binding preserved
    }

    @Test
    fun wrongIssuerKeyRejected(): Unit = runBlocking {
        val area = SoftwareSecureArea()
        val issuerKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val wrongKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val deviceKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256)).publicKey
        val bytes = issued(area, issuerKey, deviceKey)

        assertFailsWith<MdocException> {
            MdocVerifier(TestTrust(wrongKey.publicKey), now = { now }).verify(IssuerSigned.decode(bytes))
        }
    }

    @Test
    fun tamperedElementRejected(): Unit = runBlocking {
        val area = SoftwareSecureArea()
        val issuerKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val deviceKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256)).publicKey
        val bytes = issued(area, issuerKey, deviceKey)

        // flip a byte inside the nameSpaces item so its digest no longer matches the MSO
        val idx = bytes.indexOf("Jongho".encodeToByteArray())
        bytes[idx] = 'X'.code.toByte()
        assertFailsWith<MdocException> {
            MdocVerifier(TestTrust(issuerKey.publicKey), now = { now }).verify(IssuerSigned.decode(bytes))
        }
    }

    @Test
    fun expiredMdocRejected(): Unit = runBlocking {
        val area = SoftwareSecureArea()
        val issuerKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val deviceKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256)).publicKey
        val bytes = issued(area, issuerKey, deviceKey, validUntil = Instant.parse("2026-06-01T00:00:00Z"))

        assertFailsWith<MdocException> {
            MdocVerifier(TestTrust(issuerKey.publicKey), now = { Instant.parse("2026-12-01T00:00:00Z") })
                .verify(IssuerSigned.decode(bytes))
        }
    }

    private fun ByteArray.indexOf(sub: ByteArray): Int {
        outer@ for (i in 0..this.size - sub.size) {
            for (j in sub.indices) if (this[i + j] != sub[j]) continue@outer
            return i
        }
        throw AssertionError("subsequence not found")
    }
}
