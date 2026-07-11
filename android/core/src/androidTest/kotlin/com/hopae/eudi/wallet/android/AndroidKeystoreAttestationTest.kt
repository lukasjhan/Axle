package com.hopae.eudi.wallet.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.hopae.eudi.wallet.spi.KeySpec
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayInputStream
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate

/**
 * On-device verification of real Android Key Attestation (needs the hardware Keystore/TEE, so it runs as an
 * instrumented test): a key created with a challenge yields a full attestation chain carrying the Android
 * Key Attestation extension, and a challenge-less key yields none.
 */
@RunWith(AndroidJUnit4::class)
class AndroidKeystoreAttestationTest {
    private val keyAttestationExtensionOid = "1.3.6.1.4.1.11129.2.1.17"

    @Test
    fun attestsAHardwareKeyBoundToAChallenge() = runBlocking<Unit> {
        val area = AndroidKeystoreSecureArea()
        val challenge = "eudi-attestation-challenge".toByteArray()
        val key = area.createKey(KeySpec(secureArea = area.id, attestationChallenge = challenge))
        try {
            val attestation = area.attestation(key.handle, challenge)
            assertNotNull("a hardware-backed key with a challenge must attest", attestation)
            assertEquals("android-keystore-x5c", attestation!!.format)

            val certs = CertificateFactory.getInstance("X.509")
                .generateCertificates(ByteArrayInputStream(attestation.data)).toList()
            assertTrue("attestation chain has the leaf + intermediates/root, not just a self-signed leaf", certs.size >= 2)
            val leaf = certs.first() as X509Certificate
            assertNotNull("the leaf carries the Android Key Attestation extension", leaf.getExtensionValue(keyAttestationExtensionOid))
            val leafKey = leaf.publicKey as java.security.interfaces.ECPublicKey
            assertEquals("attestation leaf key matches the created key", java.math.BigInteger(1, key.publicKey.x), leafKey.w.affineX)
        } finally {
            area.deleteKey(key.handle)
        }
    }

    @Test
    fun noAttestationWithoutAChallenge() = runBlocking {
        val area = AndroidKeystoreSecureArea()
        val key = area.createKey(KeySpec(secureArea = area.id))
        try {
            assertNull("a key created without a challenge has no attestation chain", area.attestation(key.handle, ByteArray(0)))
        } finally {
            area.deleteKey(key.handle)
        }
    }
}
