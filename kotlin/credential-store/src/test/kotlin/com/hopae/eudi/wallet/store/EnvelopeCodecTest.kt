package com.hopae.eudi.wallet.store

import com.hopae.eudi.wallet.spi.CredentialFormat
import com.hopae.eudi.wallet.spi.CredentialId
import com.hopae.eudi.wallet.spi.CredentialPolicy
import com.hopae.eudi.wallet.spi.KeyHandle
import com.hopae.eudi.wallet.spi.KeyUse
import com.hopae.eudi.wallet.spi.SecureAreaId
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull

private const val GOLDEN_ISSUED_HEX =
    "a700010166637265642d310201036e75726e3a657564693a7069643a31041b0000018bcfe56800050206a200a2000201010182" +
        "a40068736f66747761726501656b65792d31024201020300a40068736f66747761726501656b65792d32024203040301"

class EnvelopeCodecTest {

    private fun sampleIssued(): CredentialEnvelope = CredentialEnvelope(
        id = CredentialId("cred-1"),
        format = CredentialFormat.SdJwtVc("urn:eudi:pid:1"),
        createdAt = Instant.ofEpochMilli(1_700_000_000_000),
        lifecycle = EnvelopeLifecycle.Issued(
            policy = CredentialPolicy(batchSize = 2, use = KeyUse.OneTime),
            instances = listOf(
                CredentialInstance(KeyHandle(SecureAreaId("software"), "key-1"), byteArrayOf(1, 2), useCount = 0),
                CredentialInstance(KeyHandle(SecureAreaId("software"), "key-2"), byteArrayOf(3, 4), useCount = 1),
            ),
        ),
    )

    @Test
    fun issuedRoundtripAndDeterminism() {
        val encoded = EnvelopeCodec.encode(sampleIssued())
        assertEquals(
            GOLDEN_ISSUED_HEX,
            encoded.joinToString("") { "%02x".format(it) },
            "cross-language golden vector (same constant in Swift EnvelopeCodecTests)",
        )

        assertContentEquals(encoded, EnvelopeCodec.encode(sampleIssued()), "encoding must be deterministic")
        assertContentEquals(encoded, EnvelopeCodec.encode(EnvelopeCodec.decode(encoded)), "decode/encode stable")

        val decoded = EnvelopeCodec.decode(encoded)
        assertEquals("cred-1", decoded.id.value)
        assertEquals(CredentialFormat.SdJwtVc("urn:eudi:pid:1"), decoded.format)
        assertEquals(1_700_000_000_000, decoded.createdAt.toEpochMilli())
        val issued = assertIs<EnvelopeLifecycle.Issued>(decoded.lifecycle)
        assertEquals(CredentialPolicy(2, KeyUse.OneTime), issued.policy)
        assertEquals(2, issued.instances.size)
        assertEquals("key-1", issued.instances[0].key.alias)
        assertContentEquals(byteArrayOf(1, 2), issued.instances[0].payload)
        assertEquals(1, issued.instances[1].useCount)
    }

    @Test
    fun pendingRoundtrip() {
        val envelope = CredentialEnvelope(
            id = CredentialId("cred-2"),
            format = CredentialFormat.MsoMdoc("org.iso.18013.5.1.mDL"),
            createdAt = Instant.ofEpochMilli(1_700_000_000_001),
            lifecycle = EnvelopeLifecycle.Pending(authorizationUrl = "https://issuer.example/authorize", resumeContext = byteArrayOf(9)),
        )
        val decoded = EnvelopeCodec.decode(EnvelopeCodec.encode(envelope))
        val pending = assertIs<EnvelopeLifecycle.Pending>(decoded.lifecycle)
        assertEquals("https://issuer.example/authorize", pending.authorizationUrl)
        assertContentEquals(byteArrayOf(9), pending.resumeContext)
    }

    @Test
    fun deferredRoundtripWithAbsentOptionals() {
        val envelope = CredentialEnvelope(
            id = CredentialId("cred-3"),
            format = CredentialFormat.MsoMdoc("eu.europa.ec.eudi.pid.1"),
            createdAt = Instant.ofEpochMilli(1_700_000_000_002),
            lifecycle = EnvelopeLifecycle.Deferred(transactionContext = byteArrayOf(7, 7), retryAfter = null),
        )
        val decoded = EnvelopeCodec.decode(EnvelopeCodec.encode(envelope))
        val deferred = assertIs<EnvelopeLifecycle.Deferred>(decoded.lifecycle)
        assertContentEquals(byteArrayOf(7, 7), deferred.transactionContext)
        assertNull(deferred.retryAfter)
    }
}
