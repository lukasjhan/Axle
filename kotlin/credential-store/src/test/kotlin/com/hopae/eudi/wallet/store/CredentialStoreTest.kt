package com.hopae.eudi.wallet.store

import com.hopae.eudi.wallet.spi.CredentialFormat
import com.hopae.eudi.wallet.spi.CredentialId
import com.hopae.eudi.wallet.spi.CredentialPolicy
import com.hopae.eudi.wallet.spi.KeyHandle
import com.hopae.eudi.wallet.spi.KeyUse
import com.hopae.eudi.wallet.spi.SecureAreaId
import com.hopae.eudi.wallet.testkit.InMemoryStorageDriver
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull

class CredentialStoreTest {

    private fun issued(id: String, use: KeyUse, batch: Int): CredentialEnvelope = CredentialEnvelope(
        id = CredentialId(id),
        format = CredentialFormat.SdJwtVc("urn:eudi:pid:1"),
        createdAt = Instant.ofEpochMilli(1_700_000_000_000),
        lifecycle = EnvelopeLifecycle.Issued(
            policy = CredentialPolicy(batchSize = batch, use = use),
            instances = (1..batch).map {
                CredentialInstance(KeyHandle(SecureAreaId("software"), "key-$it"), byteArrayOf(it.toByte()))
            },
        ),
    )

    @Test
    fun crudEmitsChanges() = runBlocking {
        val store = CredentialStore(InMemoryStorageDriver())
        val events = async { store.changes.take(3).toList() }
        yield() // let the collector subscribe

        store.save(issued("a", KeyUse.Rotate, 1))
        store.save(issued("a", KeyUse.Rotate, 1))
        store.delete(CredentialId("a"))

        val list = withTimeout(5_000) { events.await() }
        assertEquals(
            listOf(
                CredentialStoreChange.Added(CredentialId("a")),
                CredentialStoreChange.Updated(CredentialId("a")),
                CredentialStoreChange.Removed(CredentialId("a")),
            ),
            list,
        )
        assertNull(store.get(CredentialId("a")))
        assertEquals(emptyList(), store.list())
    }

    @Test
    fun rotatePolicyCyclesLeastUsedInstance() = runBlocking {
        val store = CredentialStore(InMemoryStorageDriver())
        store.save(issued("r", KeyUse.Rotate, 2))

        val first = store.consumeInstance(CredentialId("r"))!!
        assertEquals("key-1", first.instance.key.alias)
        assertEquals(2, first.remaining)

        val second = store.consumeInstance(CredentialId("r"))!!
        assertEquals("key-2", second.instance.key.alias, "rotate must pick the least-used instance")

        val third = store.consumeInstance(CredentialId("r"))!!
        assertEquals("key-1", third.instance.key.alias)

        val issued = assertIs<EnvelopeLifecycle.Issued>(store.get(CredentialId("r"))!!.lifecycle)
        assertEquals(listOf(2, 1), issued.instances.map { it.useCount })
    }

    @Test
    fun oneTimePolicyDepletesInstances() = runBlocking {
        val store = CredentialStore(InMemoryStorageDriver())
        store.save(issued("o", KeyUse.OneTime, 2))

        assertEquals(1, store.consumeInstance(CredentialId("o"))!!.remaining)
        assertEquals(0, store.consumeInstance(CredentialId("o"))!!.remaining)
        assertNull(store.consumeInstance(CredentialId("o")), "exhausted one-time credential must return null")

        val issued = assertIs<EnvelopeLifecycle.Issued>(store.get(CredentialId("o"))!!.lifecycle)
        assertEquals(0, issued.instances.size, "envelope remains for re-issuance bookkeeping")
    }

    @Test
    fun consumeOnNonIssuedReturnsNull() = runBlocking {
        val store = CredentialStore(InMemoryStorageDriver())
        store.save(
            CredentialEnvelope(
                id = CredentialId("p"),
                format = CredentialFormat.MsoMdoc("mdl"),
                createdAt = Instant.ofEpochMilli(0),
                lifecycle = EnvelopeLifecycle.Pending(null, null),
            )
        )
        assertNull(store.consumeInstance(CredentialId("p")))
        assertNull(store.consumeInstance(CredentialId("missing")))
    }
}
