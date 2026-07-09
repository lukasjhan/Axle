import Foundation
import SdJwt
import WalletAPI
import XCTest
@testable import OpenID4VP

/// OpenID4VP §5 / §5.10 JAR hardening:
///  - `typ` MUST be `oauth-authz-req+jwt`, else the wallet MUST NOT process the request object;
///  - the Request Object's `client_id` MUST equal the Authorization Request's, prefix included;
///  - `request_uri_method` is case-sensitive and must be `get` or `post`;
///  - a `wallet_nonce` sent on the POST MUST be echoed by the request object, else terminate.
final class JarHardeningTests: XCTestCase {

    private let clientId = "verifier.example"

    private final class StubTransport: HttpTransport, @unchecked Sendable {
        let jws: String
        var last: HttpRequest?
        init(_ jws: String) { self.jws = jws }
        func execute(_ request: HttpRequest) async throws -> HttpResponse {
            last = request
            return HttpResponse(status: 200, headers: [], body: Array(jws.utf8))
        }
    }

    /// Deterministic bytes → a stable wallet_nonce we can assert against.
    private struct FixedRng: Rng {
        func nextBytes(_ size: Int) -> [UInt8] { [UInt8](repeating: 7, count: size) }
    }
    private var expectedNonce: String { Base64Url.encode([UInt8](repeating: 7, count: 16)) }

    private func b64(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    private func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }

    private func claims(clientId: String? = nil, walletNonce: String? = nil) -> String {
        let cid = clientId ?? self.clientId
        let wn = walletNonce.map { #","wallet_nonce":"\#($0)""# } ?? ""
        return #"{"client_id":"\#(cid)","nonce":"n1","response_mode":"direct_post","response_uri":"https://verifier.example/response"\#(wn),"dcql_query":{"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]},"claims":[{"path":["family_name"]}]}]}}"#
    }

    private func jws(_ claims: String, typ: String? = requestObjectTyp) -> String {
        let header = typ.map { #"{"alg":"ES256","typ":"\#($0)"}"# } ?? #"{"alg":"ES256"}"#
        return "\(b64(header)).\(b64(claims)).\(b64("sig"))"
    }

    /// JAR by value (`request=`), so no HTTP is needed.
    private func byValueUri(_ jws: String, clientId: String? = nil) -> String {
        "openid4vp://?client_id=\(enc(clientId ?? self.clientId))&request=\(enc(jws))"
    }

    private func resolver(_ transport: any HttpTransport = StubTransport(""), rng: (any Rng)? = nil) -> AuthorizationRequestResolver {
        AuthorizationRequestResolver(http: transport, trust: nil, rng: rng)
    }

    private func expectInvalidRequest(_ body: () async throws -> Void, _ message: String) async {
        do {
            try await body()
            XCTFail(message)
        } catch VpError.invalidRequest {
        } catch {
            XCTFail("\(message) — got \(error)")
        }
    }

    func testAcceptsConformantRequestObject() async throws {
        let resolved = try await resolver().resolve(byValueUri(jws(claims())))
        XCTAssertEqual(clientId, resolved.clientId)
        XCTAssertEqual("n1", resolved.nonce)
    }

    func testRejectsMissingTyp() async {
        await expectInvalidRequest({ _ = try await self.resolver().resolve(self.byValueUri(self.jws(self.claims(), typ: nil))) },
                                   "missing typ must be rejected")
    }

    func testRejectsWrongTyp() async {
        await expectInvalidRequest({ _ = try await self.resolver().resolve(self.byValueUri(self.jws(self.claims(), typ: "JWT"))) },
                                   "wrong typ must be rejected")
    }

    /// §5.10.1: the prefix is part of the identifier — `verifier.example` != `x509_san_dns:verifier.example`.
    func testRejectsClientIdMismatch() async {
        let objectClaims = claims(clientId: "x509_san_dns:verifier.example")
        await expectInvalidRequest({ _ = try await self.resolver().resolve(self.byValueUri(self.jws(objectClaims))) },
                                   "client_id mismatch must be rejected")
    }

    func testRejectsRequestObjectWithoutClientId() async {
        let objectClaims = #"{"nonce":"n1","response_mode":"direct_post","response_uri":"https://v.example/r","dcql_query":{"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["x"]},"claims":[{"path":["a"]}]}]}}"#
        await expectInvalidRequest({ _ = try await self.resolver().resolve(self.byValueUri(self.jws(objectClaims))) },
                                   "request object without client_id must be rejected")
    }

    /// §8.5 `invalid_request_uri_method`: the value is case-sensitive.
    func testRejectsNonLowercaseRequestUriMethod() async {
        let uri = "openid4vp://?client_id=\(enc(clientId))&request_uri=\(enc("https://v.example/req"))&request_uri_method=POST"
        await expectInvalidRequest({ _ = try await self.resolver().resolve(uri) }, "uppercase POST must be rejected")
    }

    func testRejectsUnknownRequestUriMethod() async {
        let uri = "openid4vp://?client_id=\(enc(clientId))&request_uri=\(enc("https://v.example/req"))&request_uri_method=put"
        await expectInvalidRequest({ _ = try await self.resolver().resolve(uri) }, "unknown method must be rejected")
    }

    private func postUri() -> String {
        "openid4vp://?client_id=\(enc(clientId))&request_uri=\(enc("https://v.example/req"))&request_uri_method=post"
    }

    func testSendsWalletNonceAndAcceptsTheEcho() async throws {
        let transport = StubTransport(jws(claims(walletNonce: expectedNonce)))
        let resolved = try await resolver(transport, rng: FixedRng()).resolve(postUri())

        XCTAssertEqual("n1", resolved.nonce)
        let body = String(bytes: transport.last?.body ?? [], encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("wallet_nonce=\(enc(expectedNonce))"), "POST must carry the wallet_nonce: \(body)")
    }

    func testRejectsMissingWalletNonceEcho() async {
        let transport = StubTransport(jws(claims())) // verifier omitted wallet_nonce
        await expectInvalidRequest({ _ = try await self.resolver(transport, rng: FixedRng()).resolve(self.postUri()) },
                                   "missing wallet_nonce echo must be rejected")
    }

    func testRejectsWrongWalletNonceEcho() async {
        let transport = StubTransport(jws(claims(walletNonce: "someone-elses-nonce")))
        await expectInvalidRequest({ _ = try await self.resolver(transport, rng: FixedRng()).resolve(self.postUri()) },
                                   "wrong wallet_nonce echo must be rejected")
    }

    /// Sending the nonce is OPTIONAL: without an Rng none is sent and none is expected back.
    func testWithoutRngNoWalletNonceIsSentOrRequired() async throws {
        let transport = StubTransport(jws(claims()))
        let resolved = try await resolver(transport, rng: nil).resolve(postUri())

        XCTAssertEqual("n1", resolved.nonce)
        let body = String(bytes: transport.last?.body ?? [], encoding: .utf8) ?? ""
        XCTAssertFalse(body.contains("wallet_nonce"))
    }
}
