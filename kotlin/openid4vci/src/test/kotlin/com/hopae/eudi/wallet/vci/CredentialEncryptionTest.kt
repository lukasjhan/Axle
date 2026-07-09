package com.hopae.eudi.wallet.vci

import com.hopae.eudi.wallet.sdjwt.SecureAreaJwsSigner
import com.hopae.eudi.wallet.spi.KeySpec
import com.hopae.eudi.wallet.spi.Rng
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.testkit.SoftwareSecureArea
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * OpenID4VCI §8.2 / §10 — encrypted Credential Requests and Responses.
 *
 * The wallet sends `credential_response_encryption` with its own ephemeral JWK, and because §8.2 says
 * request encryption MUST accompany it (so the key cannot be substituted), the request itself goes out
 * as a compact JWE with the issuer's `kid` echoed in the header.
 */
class CredentialEncryptionTest {

    private val now = 1_700_000_000L
    private fun rng() = Rng { size -> ByteArray(size) { (it + 1).toByte() } }

    private suspend fun keys(area: SoftwareSecureArea): IssuanceKeys {
        val proofKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val dpopKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        return IssuanceKeys(
            SecureAreaJwsSigner(area, proofKey.handle, SigningAlgorithm.ES256), proofKey.publicKey,
            SecureAreaJwsSigner(area, dpopKey.handle, SigningAlgorithm.ES256), dpopKey.publicKey,
        )
    }

    private suspend fun issuer(area: SoftwareSecureArea, supported: Boolean, required: Boolean = false): MockIssuer {
        val issuerKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        return MockIssuer(area, issuerKey, now).apply {
            encryptionSupported = supported
            encryptionRequired = required
        }
    }

    private suspend fun issue(mock: MockIssuer, area: SoftwareSecureArea, policy: CredentialEncryption): CredentialResponse {
        val client = Openid4VciClient(mock, rng(), clock = { now }, credentialEncryption = policy)
        val offer = CredentialOffer.parse(mock.credentialOfferJson)
        return client.issueWithPreAuthorizedCode(offer, "eu.europa.ec.eudi.pid.1", keys(area), txCode = "1234")
    }

    @Test
    fun preferredEncryptsBothDirections() = runBlocking {
        val area = SoftwareSecureArea()
        val mock = issuer(area, supported = true)

        val response = issue(mock, area, CredentialEncryption.Preferred)

        assertEquals(1, response.credentials.size) // the credential survived the JWE round trip
        assertTrue(mock.seenEncryptedRequest, "§8.2: the request must be encrypted too")
        assertEquals(mock.requestEncKid, mock.seenRequestKid, "§10: the chosen JWK's kid must be echoed")
        assertEquals("A256GCM", mock.seenResponseEnc) // strongest mutually supported enc
    }

    /** The default policy leaves an issuer that merely *offers* encryption alone. */
    @Test
    fun whenRequiredStaysPlaintextIfTheIssuerDoesNotRequireIt() = runBlocking {
        val area = SoftwareSecureArea()
        val mock = issuer(area, supported = true, required = false)

        val response = issue(mock, area, CredentialEncryption.WhenRequired)

        assertEquals(1, response.credentials.size)
        assertFalse(mock.seenEncryptedRequest)
        assertEquals(null, mock.seenResponseEnc)
    }

    /** …but honours `encryption_required: true` without being asked. */
    @Test
    fun whenRequiredEncryptsIfTheIssuerRequiresIt() = runBlocking {
        val area = SoftwareSecureArea()
        val mock = issuer(area, supported = true, required = true)

        val response = issue(mock, area, CredentialEncryption.WhenRequired)

        assertEquals(1, response.credentials.size)
        assertTrue(mock.seenEncryptedRequest)
        assertEquals("A256GCM", mock.seenResponseEnc)
    }

    @Test
    fun requiredFailsAgainstAnIssuerWithoutSupport() = runBlocking<Unit> {
        val area = SoftwareSecureArea()
        val mock = issuer(area, supported = false)

        assertFailsWith<VciException.MetadataError> { issue(mock, area, CredentialEncryption.Required) }
    }

    /** A plaintext issuer stays plaintext under the default policy — no behaviour change. */
    @Test
    fun plaintextIssuerIsUnaffected() = runBlocking {
        val area = SoftwareSecureArea()
        val mock = issuer(area, supported = false)

        val response = issue(mock, area, CredentialEncryption.WhenRequired)

        assertEquals(1, response.credentials.size)
        assertFalse(mock.seenEncryptedRequest)
    }

    /** §10: the JWE `alg` must equal the chosen JWK's `alg`, and we only implement ECDH-ES. */
    @Test
    fun negotiationRejectsAnIssuerWithoutEcdhEs() = runBlocking<Unit> {
        val meta = CredentialIssuerMetadata.fromObj(
            com.hopae.eudi.wallet.sdjwt.JsonValue.parse(
                """{"credential_issuer":"https://i.example","credential_endpoint":"https://i.example/c",
                    "credential_response_encryption":{"alg_values_supported":["RSA-OAEP-256"],
                      "enc_values_supported":["A128GCM"],"encryption_required":true}}"""
            ) as com.hopae.eudi.wallet.sdjwt.JsonValue.Obj
        )
        assertFailsWith<VciException.Unsupported> {
            CredentialEncryptionSession.negotiate(CredentialEncryption.WhenRequired, meta)
        }
    }

    /** §8.2: response encryption without a request-encryption key is not a conformant configuration. */
    @Test
    fun negotiationRejectsResponseEncryptionWithoutRequestEncryption() = runBlocking<Unit> {
        val meta = CredentialIssuerMetadata.fromObj(
            com.hopae.eudi.wallet.sdjwt.JsonValue.parse(
                """{"credential_issuer":"https://i.example","credential_endpoint":"https://i.example/c",
                    "credential_response_encryption":{"alg_values_supported":["ECDH-ES"],
                      "enc_values_supported":["A128GCM"],"encryption_required":true}}"""
            ) as com.hopae.eudi.wallet.sdjwt.JsonValue.Obj
        )
        assertFailsWith<VciException.MetadataError> {
            CredentialEncryptionSession.negotiate(CredentialEncryption.WhenRequired, meta)
        }
    }
}
