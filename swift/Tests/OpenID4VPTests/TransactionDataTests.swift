import CborCose
import Foundation
import SdJwt
import WalletAPI
import WalletTestKit
import XCTest
@testable import OpenID4VP

/// OpenID4VP `transaction_data` (§8.4 / §5.1 / B.3.3): each entry is bound (as a KB-JWT hash) to exactly one
/// of its referenced credentials, and malformed / unsupported / binding-waiving entries are rejected.
final class TransactionDataTests: XCTestCase {

    private let now: Int64 = 1_700_000_000

    private func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private actor Capturing: HttpTransport {
        private(set) var vpToken: JsonValue?
        func execute(_ request: HttpRequest) async throws -> HttpResponse {
            let bodyStr = String(bytes: request.body ?? [], encoding: .utf8) ?? ""
            for pair in bodyStr.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if String(kv[0]).removingPercentEncoding == "vp_token", kv.count > 1 {
                    vpToken = try? JsonValue.parse(String(kv[1]).removingPercentEncoding ?? "")
                }
            }
            return HttpResponse(status: 200, headers: [("Content-Type", "application/json")], body: [UInt8]("{}".utf8))
        }
    }

    private func td(_ type: String, _ credentialIds: [String]) -> String {
        let ids = credentialIds.map { "\"\($0)\"" }.joined(separator: ",")
        return Base64Url.encode([UInt8](#"{"type":"\#(type)","credential_ids":[\#(ids)]}"#.utf8))
    }

    private func requestUri(_ txData: [String]?, requireBindingA: Bool? = nil) -> String {
        let bindA = requireBindingA.map { #","require_cryptographic_holder_binding":\#($0 ? "true" : "false")"# } ?? ""
        let dcql = #"{"credentials":[{"id":"a","format":"dc+sd-jwt","meta":{"vct_values":["urn:a"]},"claims":[{"path":["family_name"]}]\#(bindA)},{"id":"b","format":"dc+sd-jwt","meta":{"vct_values":["urn:b"]},"claims":[{"path":["family_name"]}]}]}"#
        let tdParam = txData.map { "&transaction_data=" + enc("[" + $0.map { s in "\"\(s)\"" }.joined(separator: ",") + "]") } ?? ""
        return "openid4vp://?client_id=verifier.example&nonce=vp-nonce-123&response_mode=direct_post&response_uri=\(enc("https://verifier.example/response"))&state=x&dcql_query=\(enc(dcql))\(tdParam)"
    }

    private func fixture(supportedTypes: Set<String>? = nil) async throws -> (Openid4VpClient, Capturing, [any PresentableCredential]) {
        let area = SoftwareSecureArea()
        let issuerKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        func issue(_ vct: String) async throws -> (SdJwt, KeyInfo) {
            let hk = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
            var n = 0
            let jwt = try await SdJwtIssuer(saltProvider: { n += 1; return "salt-\(vct)-\(n)" }).issue(
                signer: SecureAreaJwsSigner(area: area, key: issuerKey.handle, algorithm: .es256), holderKey: hk.publicKey
            ) { b in b.claim("iss", "https://issuer.example"); b.claim("vct", vct); b.sd("family_name", "Han") }
            return (jwt, hk)
        }
        let (aJwt, aKey) = try await issue("urn:a")
        let (bJwt, bKey) = try await issue("urn:b")
        let held: [any PresentableCredential] = [
            try HeldSdJwtVc(credentialId: "cred-a", sdJwt: aJwt, holderSigner: SecureAreaJwsSigner(area: area, key: aKey.handle, algorithm: .es256)),
            try HeldSdJwtVc(credentialId: "cred-b", sdJwt: bJwt, holderSigner: SecureAreaJwsSigner(area: area, key: bKey.handle, algorithm: .es256)),
        ]
        let http = Capturing()
        return (Openid4VpClient(http: http, clock: { self.now }, supportedTransactionDataTypes: supportedTypes), http, held)
    }

    private func kbClaims(_ vt: JsonValue?, _ queryId: String) throws -> JsonValue? {
        guard case let .arr(arr)? = vt?[queryId], case let .str(presentation) = arr[0] else { return nil }
        guard let kb = try SdJwt.parse(presentation).kbJwt else { return nil }
        let parts = kb.split(separator: ".")
        return try JsonValue.parse(try Base64Url.decodeToString(String(parts[1])))
    }

    private func respond(_ client: Openid4VpClient, _ uri: String, _ held: [any PresentableCredential]) async throws {
        let request = try await client.resolveRequest(uri)
        let matches = client.match(request, held: held)
        _ = try await client.respond(request: request, matches: matches, selection: .auto(matches), held: held)
    }

    func testBindsTransactionDataToReferencedCredentialOnly() async throws {
        let (client, http, held) = try await fixture()
        try await respond(client, requestUri([td("payment", ["a"])]), held)
        let vt = await http.vpToken

        guard case let .arr(aHashes)? = try kbClaims(vt, "a")?["transaction_data_hashes"] else {
            return XCTFail("referenced credential must bind the transaction_data")
        }
        XCTAssertEqual(1, aHashes.count)
        XCTAssertNil(try kbClaims(vt, "b")?["transaction_data_hashes"], "unreferenced credential must not bind it")
    }

    func testRejectsUnsupportedType() async throws {
        let (client, _, held) = try await fixture(supportedTypes: ["payment"])
        await assertInvalidTransactionData { try await self.respond(client, self.requestUri([self.td("qes_signature", ["a"])]), held) }
    }

    func testRejectsUnknownCredentialId() async throws {
        let (client, _, held) = try await fixture()
        await assertInvalidTransactionData { try await self.respond(client, self.requestUri([self.td("payment", ["does-not-exist"])]), held) }
    }

    func testRejectsMalformedEntry() async throws {
        let (client, _, held) = try await fixture()
        let bad = Base64Url.encode([UInt8](#"{"type":"payment"}"#.utf8)) // missing credential_ids
        await assertInvalidTransactionData { try await self.respond(client, self.requestUri([bad]), held) }
    }

    func testRejectsWhenReferencedQueryWaivesBinding() async throws {
        // B.3.3: transaction_data requires holder binding, so a referenced query with require...=false is invalid.
        let (client, _, held) = try await fixture()
        await assertInvalidTransactionData { try await self.respond(client, self.requestUri([self.td("payment", ["a"])], requireBindingA: false), held) }
    }

    private func assertInvalidTransactionData(_ body: () async throws -> Void) async {
        do { try await body(); XCTFail("expected invalidTransactionData") }
        catch VpError.invalidTransactionData {} catch { XCTFail("wrong error: \(error)") }
    }
}
