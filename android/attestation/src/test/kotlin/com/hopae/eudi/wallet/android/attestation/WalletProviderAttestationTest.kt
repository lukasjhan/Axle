package com.hopae.eudi.wallet.android.attestation

import com.hopae.eudi.wallet.sdjwt.Base64Url
import com.hopae.eudi.wallet.sdjwt.JsonValue
import com.hopae.eudi.wallet.spi.HttpMethod
import com.hopae.eudi.wallet.spi.HttpRequest
import com.hopae.eudi.wallet.spi.HttpResponse
import com.hopae.eudi.wallet.spi.HttpTransport
import com.hopae.eudi.wallet.spi.KeySpec
import com.hopae.eudi.wallet.testkit.SoftwareSecureArea
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpResponse.BodyHandlers

/**
 * Integration test against a locally-running `wallet-provider/` backend — proves the reference adapter
 * fetches a real WUA and a key attestation. Gated on `EUDI_WP_LIVE` so it never runs in normal CI:
 *
 *   cd wallet-provider && PORT=3200 WP_ISSUER=http://localhost:3200 npm run start
 *   cd demo && EUDI_WP_LIVE=1 ./gradlew :android:attestation:testDebugUnitTest
 */
class WalletProviderAttestationTest {
    @Test
    fun fetchesRealWuaFromLocalBackend() {
        assumeTrue("set EUDI_WP_LIVE to run against a local wallet-provider", System.getenv("EUDI_WP_LIVE") != null)
        val baseUrl = System.getenv("EUDI_WP_URL") ?: "http://localhost:3200"
        runBlocking {
            val area = SoftwareSecureArea()
            val instanceKey = area.createKey(KeySpec(secureArea = area.id))
            val provider = WalletProviderAttestation(
                baseUrl = baseUrl,
                http = JvmHttp,
                secureArea = area,
                integrity = DevIntegrityTokenProvider(),
                clientId = "wallet-dev",
            )

            // WUA: register (dev integrity) → nonce → instance-key PoP → wallet-attestation.
            val wua = provider.walletAttestation(instanceKey)
            val parts = wua.split(".")
            assertEquals("WUA is a compact JWS", 3, parts.size)
            val header = JsonValue.parse(Base64Url.decode(parts[0]).decodeToString()) as JsonValue.Obj
            assertEquals("oauth-client-attestation+jwt", (header["typ"] as JsonValue.Str).value)
            val payload = JsonValue.parse(Base64Url.decode(parts[1]).decodeToString()) as JsonValue.Obj
            val jwk = ((payload["cnf"] as JsonValue.Obj)["jwk"]) as JsonValue.Obj
            assertEquals(
                "WUA cnf binds the wallet instance key",
                Base64Url.encode(instanceKey.publicKey.x), (jwk["x"] as JsonValue.Str).value,
            )
            println("WUA OK — iss=${(payload["iss"] as? JsonValue.Str)?.value} sub=${(payload["sub"] as? JsonValue.Str)?.value}")

            // Key attestation for a batch of credential proof keys (issuer c_nonce passed through).
            val proofKeys = listOf(area.createKey(KeySpec(secureArea = area.id)), area.createKey(KeySpec(secureArea = area.id)))
            val ka = provider.keyAttestation(proofKeys, nonce = "c_nonce_123")
            assertTrue("key attestation is a JWS", ka.split(".").size == 3)
            println("Key attestation OK for ${proofKeys.size} proof keys")
        }
    }
}

/** Minimal JVM [HttpTransport] for the integration test (java.net.http). */
private object JvmHttp : HttpTransport {
    private val client = HttpClient.newHttpClient()
    override suspend fun execute(request: HttpRequest): HttpResponse {
        val builder = java.net.http.HttpRequest.newBuilder(URI.create(request.url))
        request.headers.forEach { (k, v) -> builder.header(k, v) }
        when (request.method) {
            HttpMethod.GET -> builder.GET()
            HttpMethod.POST -> builder.POST(java.net.http.HttpRequest.BodyPublishers.ofByteArray(request.body ?: ByteArray(0)))
            else -> throw UnsupportedOperationException(request.method.name)
        }
        val response = client.send(builder.build(), BodyHandlers.ofByteArray())
        val headers = response.headers().map().flatMap { (k, vs) -> vs.map { k to it } }
        return HttpResponse(response.statusCode(), headers, response.body())
    }
}
