import Foundation
import Wallet
import WalletAPI
import WalletTestKit
import XCTest

/// Phase D: reader trust — verify signed OpenID4VP request objects against configured reader anchors.
final class WalletReaderTrustTests: XCTestCase {

    private struct NoHttp: HttpTransport {
        func execute(_ request: HttpRequest) async throws -> HttpResponse { HttpResponse(status: 404, headers: [], body: []) }
    }

    /// §5: the Request Object carries its own `client_id`, identical to the Authorization Request's.
    private let requestClaims =
        #"{"client_id":"x509_san_dns:verifier.example.com","nonce":"vp-nonce-123","response_mode":"direct_post","response_uri":"https://verifier.example/response","state":"xyz","dcql_query":{"credentials":[{"id":"pid","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]},"claims":[{"path":["family_name"]}]}]}}"#

    func testSignedRequestFromTrustedReaderIsTrusted() async throws {
        let ca = try TestCerts.makeCa("Reader Root CA")
        let leaf = try TestCerts.makeLeaf(ca, cn: "EUDI Verifier", dns: "verifier.example.com")
        let wallet = Wallet.create(
            config: WalletConfig(trust: TrustConfig(readerAnchorsDer: [try ca.der])),
            ports: WalletPorts(secureAreas: [SoftwareSecureArea()], storage: InMemoryStorageDriver(), http: NoHttp()))

        let url = try await TestCerts.signedRequestUrl(leaf: leaf, clientId: "x509_san_dns:verifier.example.com", requestClaims: requestClaims)
        let session = wallet.presentation.start(url)
        var captured: PresentationRequest?
        var terminal: PresentationState?
        for await state in session.states {
            if case let .requestResolved(request) = state {
                captured = request
                session.decline()
            }
            if state.isTerminal { terminal = state; break }
        }
        let verifier = try XCTUnwrap(captured?.verifier)
        XCTAssertTrue(verifier.trusted, "reader chaining to the configured anchor must be trusted")
        XCTAssertEqual("EUDI Verifier", verifier.commonName)
        XCTAssertEqual("x509_san_dns", verifier.clientIdScheme)
        guard case .declined = terminal else { return XCTFail("terminal: \(String(describing: terminal))") }
        wallet.close()
    }

    /// Reader trust is informational, not a hard gate (see PresentationService: "Trust is informational, not a
    /// gate"): a signed request whose reader does not chain to a configured anchor still resolves — marked
    /// `verifier.trusted == false` so the user can decide — rather than being rejected outright.
    func testSignedRequestFromUntrustedReaderResolvesUntrusted() async throws {
        let trustedCa = try TestCerts.makeCa("Trusted Reader CA")
        let rogueCa = try TestCerts.makeCa("Rogue CA")
        let rogueLeaf = try TestCerts.makeLeaf(rogueCa, cn: "Rogue", dns: "verifier.example.com")
        let wallet = Wallet.create(
            config: WalletConfig(trust: TrustConfig(readerAnchorsDer: [try trustedCa.der])),
            ports: WalletPorts(secureAreas: [SoftwareSecureArea()], storage: InMemoryStorageDriver(), http: NoHttp()))

        let url = try await TestCerts.signedRequestUrl(leaf: rogueLeaf, clientId: "x509_san_dns:verifier.example.com", requestClaims: requestClaims)
        let session = wallet.presentation.start(url)
        var captured: PresentationRequest?
        var terminal: PresentationState?
        for await state in session.states {
            if case let .requestResolved(request) = state {
                captured = request
                session.decline()
            }
            if state.isTerminal { terminal = state; break }
        }
        let verifier = try XCTUnwrap(captured?.verifier)
        XCTAssertFalse(verifier.trusted, "reader not chaining to the configured anchor must be untrusted")
        guard case .declined = terminal else { return XCTFail("terminal: \(String(describing: terminal))") }
        wallet.close()
    }
}
