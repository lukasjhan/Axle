package com.hopae.eudi.wallet

import com.hopae.eudi.wallet.spi.CredentialFormat
import com.hopae.eudi.wallet.spi.CredentialId
import com.hopae.eudi.wallet.spi.CredentialPolicy
import com.hopae.eudi.wallet.spi.HttpRequest
import com.hopae.eudi.wallet.spi.HttpResponse
import com.hopae.eudi.wallet.spi.HttpTransport
import com.hopae.eudi.wallet.spi.KeySpec
import com.hopae.eudi.wallet.spi.KeyUse
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.store.CredentialEnvelope
import com.hopae.eudi.wallet.store.CredentialInstance
import com.hopae.eudi.wallet.store.CredentialStore
import com.hopae.eudi.wallet.store.EnvelopeLifecycle
import com.hopae.eudi.wallet.testkit.InMemoryStorageDriver
import com.hopae.eudi.wallet.testkit.SoftwareSecureArea
import kotlinx.coroutines.test.runTest
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Phase A: assemble a Wallet and read stored credentials back as the facade view. */
class WalletCredentialsTest {

    private val noHttp = object : HttpTransport {
        override suspend fun execute(request: HttpRequest): HttpResponse = error("http not used in Phase A test")
    }

    @Test
    fun assembleListGetFilterDelete() = runTest {
        val area = SoftwareSecureArea()
        val storage = InMemoryStorageDriver()

        // seed a credential through the underlying store (issuance is Phase B)
        val key = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val id = CredentialId("cred-1")
        CredentialStore(storage).save(
            CredentialEnvelope(
                id = id,
                format = CredentialFormat.SdJwtVc("eu.europa.ec.eudi.pid.1"),
                createdAt = Instant.parse("2026-01-01T00:00:00Z"),
                lifecycle = EnvelopeLifecycle.Issued(
                    policy = CredentialPolicy(batchSize = 3, use = KeyUse.OneTime),
                    instances = listOf(CredentialInstance(key.handle, byteArrayOf(1, 2, 3))),
                ),
            ),
        )

        val wallet = Wallet.create(WalletConfig(), WalletPorts(listOf(area), storage, noHttp))

        // list + view
        val all = wallet.credentials.list()
        assertEquals(1, all.size)
        val c = wallet.credentials.get(id)!!
        assertEquals(id, c.id)
        assertEquals(CredentialFormat.SdJwtVc("eu.europa.ec.eudi.pid.1"), c.format)
        val issued = c.lifecycle as Lifecycle.Issued
        assertEquals(1, issued.instances.remaining)
        assertEquals(KeyUse.OneTime, issued.instances.use)

        // filter
        assertEquals(1, wallet.credentials.list(CredentialFilter.byVct("eu.europa.ec.eudi.pid.1")).size)
        assertTrue(wallet.credentials.list(CredentialFilter.byVct("other")).isEmpty())
        assertTrue(wallet.credentials.list(CredentialFilter.byDocType("org.iso.18013.5.1.mDL")).isEmpty())

        // delete
        wallet.credentials.delete(id)
        assertNull(wallet.credentials.get(id))
        assertTrue(wallet.credentials.list().isEmpty())
    }
}
