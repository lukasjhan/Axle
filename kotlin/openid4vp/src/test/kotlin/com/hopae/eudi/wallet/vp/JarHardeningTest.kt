package com.hopae.eudi.wallet.vp

import com.hopae.eudi.wallet.spi.HttpRequest
import com.hopae.eudi.wallet.spi.HttpResponse
import com.hopae.eudi.wallet.spi.HttpTransport
import com.hopae.eudi.wallet.spi.Rng
import kotlinx.coroutines.runBlocking
import java.net.URLEncoder
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * OpenID4VP §5 / §5.10 JAR hardening:
 *  - `typ` MUST be `oauth-authz-req+jwt`, else the wallet MUST NOT process the request object;
 *  - the Request Object's `client_id` MUST equal the Authorization Request's, prefix included;
 *  - `request_uri_method` is case-sensitive and must be `get` or `post`;
 *  - a `wallet_nonce` sent on the POST MUST be echoed by the request object, else terminate.
 */
class JarHardeningTest {

    private val clientId = "verifier.example"

    private class StubTransport(private val jws: String) : HttpTransport {
        var last: HttpRequest? = null
        override suspend fun execute(request: HttpRequest): HttpResponse {
            last = request
            return HttpResponse(200, emptyList(), jws.encodeToByteArray())
        }
    }

    /** Deterministic bytes → a stable wallet_nonce we can assert against. */
    private fun rng() = Rng { size -> ByteArray(size) { 7 } }
    private val expectedNonce = com.hopae.eudi.wallet.sdjwt.Base64Url.encode(ByteArray(16) { 7 })

    private fun b64(s: String) = Base64.getUrlEncoder().withoutPadding().encodeToString(s.encodeToByteArray())
    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    private fun claims(clientId: String = this.clientId, walletNonce: String? = null): String {
        val wn = walletNonce?.let { ""","wallet_nonce":"$it"""" } ?: ""
        return """{"client_id":"$clientId","nonce":"n1","response_mode":"direct_post",""" +
            """"response_uri":"https://verifier.example/response"$wn,""" +
            """"dcql_query":{"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]},"claims":[{"path":["family_name"]}]}]}}"""
    }

    private fun jws(claims: String, typ: String? = REQUEST_OBJECT_TYP): String {
        val header = if (typ == null) """{"alg":"ES256"}""" else """{"alg":"ES256","typ":"$typ"}"""
        return "${b64(header)}.${b64(claims)}.${b64("sig")}"
    }

    /** JAR by value (`request=`), so no HTTP is needed. */
    private fun byValueUri(jws: String, clientId: String = this.clientId) =
        "openid4vp://?client_id=${enc(clientId)}&request=${enc(jws)}"

    private fun resolver(transport: HttpTransport = StubTransport(""), rng: Rng? = null) =
        AuthorizationRequestResolver(transport, trust = null, rng = rng)

    @Test
    fun acceptsConformantRequestObject() = runBlocking {
        val resolved = resolver().resolve(byValueUri(jws(claims())))
        assertEquals(clientId, resolved.clientId)
        assertEquals("n1", resolved.nonce)
    }

    @Test
    fun rejectsMissingTyp() = runBlocking<Unit> {
        assertFailsWith<VpException.InvalidRequest> { resolver().resolve(byValueUri(jws(claims(), typ = null))) }
    }

    @Test
    fun rejectsWrongTyp() = runBlocking<Unit> {
        assertFailsWith<VpException.InvalidRequest> { resolver().resolve(byValueUri(jws(claims(), typ = "JWT"))) }
    }

    /** §5.10.1: the prefix is part of the identifier — `verifier.example` != `x509_san_dns:verifier.example`. */
    @Test
    fun rejectsClientIdMismatch() = runBlocking<Unit> {
        val objectClaims = claims(clientId = "x509_san_dns:verifier.example")
        assertFailsWith<VpException.InvalidRequest> { resolver().resolve(byValueUri(jws(objectClaims))) }
    }

    @Test
    fun rejectsRequestObjectWithoutClientId() = runBlocking<Unit> {
        val objectClaims = """{"nonce":"n1","response_mode":"direct_post","response_uri":"https://v.example/r",""" +
            """"dcql_query":{"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["x"]},"claims":[{"path":["a"]}]}]}}"""
        assertFailsWith<VpException.InvalidRequest> { resolver().resolve(byValueUri(jws(objectClaims))) }
    }

    /** §8.5 `invalid_request_uri_method`: the value is case-sensitive. */
    @Test
    fun rejectsNonLowercaseRequestUriMethod() = runBlocking<Unit> {
        val uri = "openid4vp://?client_id=${enc(clientId)}&request_uri=${enc("https://v.example/req")}&request_uri_method=POST"
        assertFailsWith<VpException.InvalidRequest> { resolver().resolve(uri) }
    }

    @Test
    fun rejectsUnknownRequestUriMethod() = runBlocking<Unit> {
        val uri = "openid4vp://?client_id=${enc(clientId)}&request_uri=${enc("https://v.example/req")}&request_uri_method=put"
        assertFailsWith<VpException.InvalidRequest> { resolver().resolve(uri) }
    }

    private fun postUri() =
        "openid4vp://?client_id=${enc(clientId)}&request_uri=${enc("https://v.example/req")}&request_uri_method=post"

    @Test
    fun sendsWalletNonceAndAcceptsTheEcho() = runBlocking {
        val transport = StubTransport(jws(claims(walletNonce = expectedNonce)))
        val resolved = resolver(transport, rng()).resolve(postUri())

        assertEquals("n1", resolved.nonce)
        val body = transport.last?.body?.decodeToString() ?: ""
        assertTrue(body.contains("wallet_nonce=${enc(expectedNonce)}"), "POST must carry the wallet_nonce: $body")
    }

    @Test
    fun rejectsMissingWalletNonceEcho() = runBlocking<Unit> {
        val transport = StubTransport(jws(claims())) // verifier omitted wallet_nonce
        assertFailsWith<VpException.InvalidRequest> { resolver(transport, rng()).resolve(postUri()) }
    }

    @Test
    fun rejectsWrongWalletNonceEcho() = runBlocking<Unit> {
        val transport = StubTransport(jws(claims(walletNonce = "someone-elses-nonce")))
        assertFailsWith<VpException.InvalidRequest> { resolver(transport, rng()).resolve(postUri()) }
    }

    /** Sending the nonce is OPTIONAL: without an Rng none is sent and none is expected back. */
    @Test
    fun withoutRngNoWalletNonceIsSentOrRequired() = runBlocking {
        val transport = StubTransport(jws(claims()))
        val resolved = resolver(transport, rng = null).resolve(postUri())

        assertEquals("n1", resolved.nonce)
        assertTrue(!(transport.last?.body?.decodeToString() ?: "").contains("wallet_nonce"))
    }
}
