package com.hopae.eudi.wallet.vp

import com.hopae.eudi.wallet.sdjwt.JsonValue
import com.hopae.eudi.wallet.sdjwt.SdJwt
import com.hopae.eudi.wallet.sdjwt.SdJwtIssuer
import com.hopae.eudi.wallet.sdjwt.SecureAreaJwsSigner
import com.hopae.eudi.wallet.spi.HttpRequest
import com.hopae.eudi.wallet.spi.HttpResponse
import com.hopae.eudi.wallet.spi.HttpTransport
import com.hopae.eudi.wallet.spi.KeyInfo
import com.hopae.eudi.wallet.spi.KeySpec
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.testkit.SoftwareSecureArea
import kotlinx.coroutines.runBlocking
import java.net.URLDecoder
import java.net.URLEncoder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/**
 * OpenID4VP DCQL `multiple` (§6.1/§8.1): a `multiple: true` query may return several matching credentials
 * in the vp_token array; a `multiple: false` (default) query returns exactly one.
 */
class DcqlMultipleTest {

    private val now = 1_700_000_000L
    private val clientId = "verifier.example"
    private val nonce = "vp-nonce-123"
    private val responseUri = "https://verifier.example/response"

    /** Captures the posted vp_token without verifying it. */
    private class Capturing : HttpTransport {
        var vpToken: JsonValue.Obj? = null; private set
        override suspend fun execute(request: HttpRequest): HttpResponse {
            val form = request.body!!.decodeToString().split('&').associate {
                URLDecoder.decode(it.substringBefore('='), "UTF-8") to URLDecoder.decode(it.substringAfter('='), "UTF-8")
            }
            vpToken = JsonValue.parse(form["vp_token"]!!) as JsonValue.Obj
            return HttpResponse(200, listOf("Content-Type" to "application/json"), "{}".encodeToByteArray())
        }
    }

    private fun issuePid(area: SoftwareSecureArea, issuerKey: KeyInfo, holderKey: KeyInfo, familyName: String): SdJwt = runBlocking {
        var n = 0
        SdJwtIssuer({ "salt-${familyName}-${++n}" }).issue(
            signer = SecureAreaJwsSigner(area, issuerKey.handle, SigningAlgorithm.ES256),
            holderKey = holderKey.publicKey,
        ) {
            claim("iss", "https://issuer.example")
            claim("vct", "urn:eudi:pid:1")
            sd("family_name", familyName)
            sd("given_name", "Jongho")
        }
    }

    private fun requestUri(multiple: Boolean): String {
        val mult = if (multiple) ""","multiple":true""" else ""
        val dcql = """{"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]},
            "claims":[{"path":["family_name"]}]$mult}]}"""
        return "openid4vp://?client_id=${enc(clientId)}&nonce=${enc(nonce)}" +
            "&response_mode=direct_post&response_uri=${enc(responseUri)}&state=xyz&dcql_query=${enc(dcql)}"
    }

    /** Two held PIDs and a client wired to a capturing transport. */
    private fun fixture(): Triple<Openid4VpClient, Capturing, List<PresentableCredential>> = runBlocking {
        val area = SoftwareSecureArea()
        val issuerKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val h1 = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val h2 = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        val held = listOf(
            HeldSdJwtVc("pid-1", issuePid(area, issuerKey, h1, "Han"), SecureAreaJwsSigner(area, h1.handle, SigningAlgorithm.ES256)),
            HeldSdJwtVc("pid-2", issuePid(area, issuerKey, h2, "Kim"), SecureAreaJwsSigner(area, h2.handle, SigningAlgorithm.ES256)),
        )
        val http = Capturing()
        Triple(Openid4VpClient(http, clock = { now }), http, held)
    }

    private fun pidArray(http: Capturing) = (http.vpToken!!["pid"] as JsonValue.Arr).items

    @Test
    fun multipleTrueReturnsAllMatchingCredentials() = runBlocking {
        val (client, http, held) = fixture()
        val request = client.resolveRequest(requestUri(multiple = true))
        val matches = client.match(request, held)
        assertEquals(2, matches.candidatesByQuery["pid"]!!.size, "both PIDs match")

        client.respond(request, matches, PresentationSelection.auto(matches), held)
        assertEquals(2, pidArray(http).size, "multiple:true returns both matching credentials")
    }

    @Test
    fun multipleFalseReturnsExactlyOne() = runBlocking {
        val (client, http, held) = fixture()
        val request = client.resolveRequest(requestUri(multiple = false))
        val matches = client.match(request, held)
        assertEquals(2, matches.candidatesByQuery["pid"]!!.size, "both PIDs still match")

        client.respond(request, matches, PresentationSelection.auto(matches), held)
        assertEquals(1, pidArray(http).size, "multiple omitted → exactly one presentation")
    }

    @Test
    fun rejectsMultipleSelectionForSingleQuery(): Unit = runBlocking {
        val (client, _, held) = fixture()
        val request = client.resolveRequest(requestUri(multiple = false))
        val matches = client.match(request, held)

        // Selecting two credentials for a non-multiple query violates §8.1 — the client refuses.
        val selection = PresentationSelection(mapOf("pid" to listOf("pid-1", "pid-2")))
        assertFailsWith<VpException.InvalidRequest> {
            client.respond(request, matches, selection, held)
        }
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
}
