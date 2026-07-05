import CborCose
import CredentialStore
import Foundation
import SdJwt
import Wallet
import WalletAPI
import WalletTestKit
import XCTest

/// Phase A: assemble a Wallet, read stored credentials as the facade view, DCQL retrieval, status.
final class WalletTests: XCTestCase {

    private struct NoHttp: HttpTransport {
        func execute(_ request: HttpRequest) async throws -> HttpResponse {
            throw NSError(domain: "http not used in Phase A test", code: 0)
        }
    }

    private let now = MdocTestIssuer.isoFormatter.date(from: "2026-06-01T00:00:00Z")!

    private func seedSdJwtPid(_ area: SoftwareSecureArea, _ storage: InMemoryStorageDriver) async throws -> CredentialId {
        let issuerKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let holderKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        var n = 0
        let sdJwt = try await SdJwtIssuer(saltProvider: { n += 1; return "salt-\(n)" })
            .issue(signer: SecureAreaJwsSigner(area: area, key: issuerKey.handle, algorithm: .es256)) { b in
                b.claim("vct", "urn:eudi:pid:1")
                b.sd("family_name", "Han")
                b.sd("given_name", "Jongho")
            }
        let id = CredentialId("pid-1")
        try await DefaultCredentialStore(driver: storage).save(CredentialEnvelope(
            id: id, format: .sdJwtVc(vct: "urn:eudi:pid:1"), createdAt: now,
            lifecycle: .issued(policy: CredentialPolicy(), instances: [CredentialInstance(key: holderKey.handle, payload: Array(sdJwt.serialize().utf8))])))
        return id
    }

    private func seedMdocMdl(_ area: SoftwareSecureArea, _ storage: InMemoryStorageDriver) async throws -> CredentialId {
        let issuerKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let deviceKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let bytes = try await MdocTestIssuer.issue(
            area: area, issuerKey: issuerKey, deviceKey: deviceKey.publicKey,
            docType: "org.iso.18013.5.1.mDL", namespace: "org.iso.18013.5.1",
            elements: [("family_name", .text("Kim")), ("given_name", .text("Minsu"))],
            x5chain: [[0x30, 0x01]], signed: now, validFrom: now, validUntil: now.addingTimeInterval(31_536_000))
        let id = CredentialId("mdl-1")
        try await DefaultCredentialStore(driver: storage).save(CredentialEnvelope(
            id: id, format: .msoMdoc(docType: "org.iso.18013.5.1.mDL"), createdAt: now,
            lifecycle: .issued(policy: CredentialPolicy(), instances: [CredentialInstance(key: deviceKey.handle, payload: bytes)])))
        return id
    }

    func testParsedClaimsDcqlMatchStatusAndCrud() async throws {
        let area = SoftwareSecureArea()
        let storage = InMemoryStorageDriver()
        let pidId = try await seedSdJwtPid(area, storage)
        let mdlId = try await seedMdocMdl(area, storage)
        let wallet = Wallet.create(config: WalletConfig(), ports: WalletPorts(secureAreas: [area], storage: storage, http: NoHttp()))

        // claims view — parsed from payload
        let pid = try await wallet.credentials.get(pidId)!
        guard case let .issued(pidClaims, _, pidInstances) = pid.lifecycle else { return XCTFail("pid not issued") }
        XCTAssertEqual(1, pidInstances.remaining)
        XCTAssertTrue(pidClaims.contains { $0.path == ["family_name"] && $0.value.display() == "Han" }, "PID family_name")
        let mdl = try await wallet.credentials.get(mdlId)!
        guard case let .issued(mdlClaims, _, _) = mdl.lifecycle else { return XCTFail("mdl not issued") }
        XCTAssertTrue(mdlClaims.contains { $0.path == ["org.iso.18013.5.1", "family_name"] && $0.value.display() == "Kim" }, "mDL family_name")

        // filter
        let byPid = try await wallet.credentials.list(filter: .byVct("urn:eudi:pid:1"))
        XCTAssertEqual(1, byPid.count)
        let byOther = try await wallet.credentials.list(filter: .byVct("other"))
        XCTAssertTrue(byOther.isEmpty)

        // DCQL match — PID SD-JWT query matches only the PID
        let pidQuery = #"{"credentials":[{"id":"q","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]},"claims":[{"path":["family_name"]}]}]}"#
        let m = try await wallet.credentials.match(pidQuery)
        XCTAssertTrue(m.satisfiable)
        let cands = m.byQuery["q"]!
        XCTAssertEqual(1, cands.count)
        XCTAssertEqual(pidId, cands[0].credential.id)
        XCTAssertEqual([["family_name"]], cands[0].disclosedPaths)

        // DCQL match — mdoc query matches only the mDL
        let mdlQuery = #"{"credentials":[{"id":"q","format":"mso_mdoc","meta":{"doctype_value":"org.iso.18013.5.1.mDL"},"claims":[{"path":["org.iso.18013.5.1","family_name"]}]}]}"#
        let m2 = try await wallet.credentials.match(mdlQuery)
        XCTAssertEqual(mdlId, m2.byQuery["q"]!.first!.credential.id)

        // status — no status_list claim → valid (no network)
        let status = try await wallet.credentials.status(pidId)
        XCTAssertEqual(CredentialStatus.valid, status)

        // delete
        try await wallet.credentials.delete(pidId)
        let afterDelete = try await wallet.credentials.get(pidId)
        XCTAssertNil(afterDelete)
        let remaining = try await wallet.credentials.list()
        XCTAssertEqual(1, remaining.count)
    }
}
