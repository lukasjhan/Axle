package com.hopae.eudi.wallet.vp

import com.hopae.eudi.wallet.sdjwt.Base64Url
import com.hopae.eudi.wallet.sdjwt.JsonValue
import com.hopae.eudi.wallet.sdjwt.SdJwt
import com.hopae.eudi.wallet.sdjwt.SdJwtIssuer
import com.hopae.eudi.wallet.sdjwt.SecureAreaJwsSigner
import com.hopae.eudi.wallet.spi.HttpRequest
import com.hopae.eudi.wallet.spi.HttpResponse
import com.hopae.eudi.wallet.spi.HttpTransport
import com.hopae.eudi.wallet.spi.KeySpec
import com.hopae.eudi.wallet.spi.SigningAlgorithm
import com.hopae.eudi.wallet.testkit.SoftwareSecureArea
import kotlinx.coroutines.runBlocking
import java.net.URLDecoder
import java.net.URLEncoder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * OpenID4VP `transaction_data` (§8.4 / §5.1 / B.3.3): each entry is bound (as a KB-JWT hash) to exactly one
 * of its referenced credentials, and malformed / unsupported / binding-waiving entries are rejected.
 */
class TransactionDataTest {

    private val now = 1_700_000_000L

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

    private fun td(type: String, credentialIds: List<String>): String {
        val ids = credentialIds.joinToString(",") { "\"$it\"" }
        return Base64Url.encode("""{"type":"$type","credential_ids":[$ids]}""".encodeToByteArray())
    }

    /** DCQL with two SD-JWT VC queries `a` (vct urn:a) and `b` (vct urn:b), plus an optional transaction_data array. */
    private fun requestUri(txData: List<String>?, requireBindingA: Boolean? = null): String {
        val bindA = requireBindingA?.let { ""","require_cryptographic_holder_binding":$it""" } ?: ""
        val dcql = """{"credentials":[
            {"id":"a","format":"dc+sd-jwt","meta":{"vct_values":["urn:a"]},"claims":[{"path":["family_name"]}]$bindA},
            {"id":"b","format":"dc+sd-jwt","meta":{"vct_values":["urn:b"]},"claims":[{"path":["family_name"]}]}]}"""
        val td = txData?.let { "&transaction_data=" + enc("[" + it.joinToString(",") { s -> "\"$s\"" } + "]") } ?: ""
        return "openid4vp://?client_id=verifier.example&nonce=vp-nonce-123&response_mode=direct_post" +
            "&response_uri=${enc("https://verifier.example/response")}&state=x&dcql_query=${enc(dcql)}$td"
    }

    private fun fixture(supportedTypes: Set<String>? = null): Triple<Openid4VpClient, Capturing, List<PresentableCredential>> = runBlocking {
        val area = SoftwareSecureArea()
        val issuerKey = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
        fun issue(vct: String) = runBlocking {
            val hk = area.createKey(KeySpec(secureArea = area.id, algorithm = SigningAlgorithm.ES256))
            var n = 0
            SdJwtIssuer({ "salt-$vct-${++n}" }).issue(
                signer = SecureAreaJwsSigner(area, issuerKey.handle, SigningAlgorithm.ES256), holderKey = hk.publicKey,
            ) { claim("iss", "https://issuer.example"); claim("vct", vct); sd("family_name", "Han") } to hk
        }
        val (aJwt, aKey) = issue("urn:a"); val (bJwt, bKey) = issue("urn:b")
        val held = listOf(
            HeldSdJwtVc("cred-a", aJwt, SecureAreaJwsSigner(area, aKey.handle, SigningAlgorithm.ES256)),
            HeldSdJwtVc("cred-b", bJwt, SecureAreaJwsSigner(area, bKey.handle, SigningAlgorithm.ES256)),
        )
        val http = Capturing()
        Triple(Openid4VpClient(http, clock = { now }, supportedTransactionDataTypes = supportedTypes), http, held)
    }

    /** The KB-JWT payload of the presentation for [queryId], or null when there is no KB-JWT. */
    private fun kbClaims(http: Capturing, queryId: String): JsonValue.Obj? {
        val presentation = ((http.vpToken!![queryId] as JsonValue.Arr).items.first() as JsonValue.Str).value
        val kb = SdJwt.parse(presentation).kbJwt ?: return null
        return JsonValue.parse(Base64Url.decodeToString(kb.substringAfter('.').substringBefore('.'))) as JsonValue.Obj
    }

    @Test
    fun bindsTransactionDataToReferencedCredentialOnly() = runBlocking {
        val (client, http, held) = fixture()
        val request = client.resolveRequest(requestUri(listOf(td("payment", listOf("a")))))
        client.respond(request, client.match(request, held), PresentationSelection.auto(client.match(request, held)), held)

        // query "a" is referenced → its KB-JWT carries the hash; query "b" is not → no hash.
        val aHashes = kbClaims(http, "a")!!["transaction_data_hashes"] as? JsonValue.Arr
        assertNotNull(aHashes, "referenced credential binds the transaction_data")
        assertEquals(1, aHashes.items.size)
        assertNull(kbClaims(http, "b")!!["transaction_data_hashes"], "unreferenced credential must not bind it")
    }

    @Test
    fun rejectsUnsupportedType(): Unit = runBlocking {
        val (client, _, held) = fixture(supportedTypes = setOf("payment"))
        val request = client.resolveRequest(requestUri(listOf(td("qes_signature", listOf("a")))))
        assertFailsWith<VpException.InvalidTransactionData> {
            client.respond(request, client.match(request, held), PresentationSelection.auto(client.match(request, held)), held)
        }
    }

    @Test
    fun rejectsUnknownCredentialId(): Unit = runBlocking {
        val (client, _, held) = fixture()
        val request = client.resolveRequest(requestUri(listOf(td("payment", listOf("does-not-exist")))))
        assertFailsWith<VpException.InvalidTransactionData> {
            client.respond(request, client.match(request, held), PresentationSelection.auto(client.match(request, held)), held)
        }
    }

    @Test
    fun rejectsMalformedEntry(): Unit = runBlocking {
        val (client, _, held) = fixture()
        val bad = Base64Url.encode("""{"type":"payment"}""".encodeToByteArray()) // missing credential_ids
        val request = client.resolveRequest(requestUri(listOf(bad)))
        assertFailsWith<VpException.InvalidTransactionData> {
            client.respond(request, client.match(request, held), PresentationSelection.auto(client.match(request, held)), held)
        }
    }

    @Test
    fun rejectsWhenReferencedQueryWaivesBinding(): Unit = runBlocking {
        // B.3.3: transaction_data requires holder binding, so a referenced query with require...=false is invalid.
        val (client, _, held) = fixture()
        val request = client.resolveRequest(requestUri(listOf(td("payment", listOf("a"))), requireBindingA = false))
        assertFailsWith<VpException.InvalidTransactionData> {
            client.respond(request, client.match(request, held), PresentationSelection.auto(client.match(request, held)), held)
        }
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
}
