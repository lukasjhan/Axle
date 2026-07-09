import CborCose
import Foundation
import SdJwt
import WalletAPI
import WalletTestKit
import XCTest
@testable import OpenID4VP

/// OpenID4VP DCQL `multiple` (§6.1/§8.1): a `multiple: true` query may return several matching credentials
/// in the vp_token array; a `multiple: false` (default) query returns exactly one.
final class DcqlMultipleTests: XCTestCase {

    private let now: Int64 = 1_700_000_000
    private let clientId = "verifier.example"
    private let nonce = "vp-nonce-123"
    private let responseUri = "https://verifier.example/response"

    private func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Captures the posted vp_token without verifying it.
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

    private func issuePid(_ area: SoftwareSecureArea, _ issuerKey: KeyInfo, _ holderKey: KeyInfo, _ familyName: String) async throws -> SdJwt {
        var n = 0
        let salts: () -> String = { n += 1; return "salt-\(familyName)-\(n)" }
        return try await SdJwtIssuer(saltProvider: salts).issue(
            signer: SecureAreaJwsSigner(area: area, key: issuerKey.handle, algorithm: .es256),
            holderKey: holderKey.publicKey
        ) { b in
            b.claim("iss", "https://issuer.example")
            b.claim("vct", "urn:eudi:pid:1")
            b.sd("family_name", familyName)
            b.sd("given_name", "Jongho")
        }
    }

    private func requestUri(multiple: Bool) -> String {
        let mult = multiple ? #","multiple":true"# : ""
        let dcql = #"{"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]},"claims":[{"path":["family_name"]}]\#(mult)}]}"#
        return "openid4vp://?client_id=\(enc(clientId))&nonce=\(enc(nonce))&response_mode=direct_post&response_uri=\(enc(responseUri))&state=xyz&dcql_query=\(enc(dcql))"
    }

    /// Two held PIDs and a client wired to a capturing transport.
    private func fixture() async throws -> (Openid4VpClient, Capturing, [any PresentableCredential]) {
        let area = SoftwareSecureArea()
        let issuerKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let h1 = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let h2 = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let held: [any PresentableCredential] = [
            try HeldSdJwtVc(credentialId: "pid-1", sdJwt: try await issuePid(area, issuerKey, h1, "Han"),
                            holderSigner: SecureAreaJwsSigner(area: area, key: h1.handle, algorithm: .es256)),
            try HeldSdJwtVc(credentialId: "pid-2", sdJwt: try await issuePid(area, issuerKey, h2, "Kim"),
                            holderSigner: SecureAreaJwsSigner(area: area, key: h2.handle, algorithm: .es256)),
        ]
        let http = Capturing()
        return (Openid4VpClient(http: http, clock: { self.now }), http, held)
    }

    private func pidCount(_ vt: JsonValue?) -> Int? {
        guard case let .arr(arr)? = vt?["pid"] else { return nil }
        return arr.count
    }

    func testMultipleTrueReturnsAllMatchingCredentials() async throws {
        let (client, http, held) = try await fixture()
        let request = try await client.resolveRequest(requestUri(multiple: true))
        let matches = client.match(request, held: held)
        XCTAssertEqual(2, matches.candidatesByQuery["pid"]?.count, "both PIDs match")

        _ = try await client.respond(request: request, matches: matches, selection: .auto(matches), held: held)
        let vt = await http.vpToken
        XCTAssertEqual(2, pidCount(vt), "multiple:true returns both matching credentials")
    }

    func testMultipleFalseReturnsExactlyOne() async throws {
        let (client, http, held) = try await fixture()
        let request = try await client.resolveRequest(requestUri(multiple: false))
        let matches = client.match(request, held: held)
        XCTAssertEqual(2, matches.candidatesByQuery["pid"]?.count, "both PIDs still match")

        _ = try await client.respond(request: request, matches: matches, selection: .auto(matches), held: held)
        let vt = await http.vpToken
        XCTAssertEqual(1, pidCount(vt), "multiple omitted → exactly one presentation")
    }

    func testRejectsMultipleSelectionForSingleQuery() async throws {
        let (client, _, held) = try await fixture()
        let request = try await client.resolveRequest(requestUri(multiple: false))
        let matches = client.match(request, held: held)

        // Selecting two credentials for a non-multiple query violates §8.1 — the client refuses.
        let selection = PresentationSelection(chosen: ["pid": ["pid-1", "pid-2"]])
        do {
            _ = try await client.respond(request: request, matches: matches, selection: selection, held: held)
            XCTFail("should reject a multi-credential selection for a single-valued query")
        } catch VpError.invalidRequest {
            // expected
        }
    }
}
