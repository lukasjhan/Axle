import CborCose
import Foundation
import SdJwt
import WalletAPI
import WalletTestKit
import XCTest
@testable import OpenID4VCI

/// OpenID4VCI §8.2 / §10 — encrypted Credential Requests and Responses.
///
/// The wallet sends `credential_response_encryption` with its own ephemeral JWK, and because §8.2 says
/// request encryption MUST accompany it (so the key cannot be substituted), the request itself goes out
/// as a compact JWE with the issuer's `kid` echoed in the header.
final class CredentialEncryptionTests: XCTestCase {

    private let now: Int64 = 1_700_000_000

    private struct TestRng: Rng {
        func nextBytes(_ size: Int) -> [UInt8] { (0..<size).map { UInt8(($0 + 1) & 0xff) } }
    }

    private func makeKeys(_ area: SoftwareSecureArea) async throws -> IssuanceKeys {
        let proofKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let dpopKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        return IssuanceKeys(
            proofSigner: SecureAreaJwsSigner(area: area, key: proofKey.handle, algorithm: .es256), proofPublicKey: proofKey.publicKey,
            dpopSigner: SecureAreaJwsSigner(area: area, key: dpopKey.handle, algorithm: .es256), dpopPublicKey: dpopKey.publicKey)
    }

    private func issuer(_ area: SoftwareSecureArea, supported: Bool, required: Bool = false) async throws -> MockIssuer {
        let issuerKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let mock = MockIssuer(area: area, issuerKey: issuerKey, now: now)
        await mock.setEncryption(supported: supported, required: required)
        return mock
    }

    private func issue(_ mock: MockIssuer, _ area: SoftwareSecureArea, _ policy: CredentialEncryption) async throws -> CredentialResponse {
        let client = Openid4VciClient(http: mock, rng: TestRng(), clock: { self.now }, credentialEncryption: policy)
        let offer = try CredentialOffer.parse(mock.credentialOfferJson)
        return try await client.issueWithPreAuthorizedCode(
            offer: offer, configurationId: "eu.europa.ec.eudi.pid.1", keys: try await makeKeys(area), txCode: "1234")
    }

    func testPreferredEncryptsBothDirections() async throws {
        let area = SoftwareSecureArea()
        let mock = try await issuer(area, supported: true)

        let response = try await issue(mock, area, .preferred)

        XCTAssertEqual(1, response.credentials.count) // the credential survived the JWE round trip
        let encryptedRequest = await mock.seenEncryptedRequest
        XCTAssertTrue(encryptedRequest, "§8.2: the request must be encrypted too")
        let kid = await mock.seenRequestKid
        let expectedKid = await mock.requestEncKid
        XCTAssertEqual(expectedKid, kid, "§10: the chosen JWK's kid must be echoed")
        let enc = await mock.seenResponseEnc
        XCTAssertEqual("A256GCM", enc) // strongest mutually supported enc
    }

    /// The default policy leaves an issuer that merely *offers* encryption alone.
    func testWhenRequiredStaysPlaintextIfTheIssuerDoesNotRequireIt() async throws {
        let area = SoftwareSecureArea()
        let mock = try await issuer(area, supported: true, required: false)

        let response = try await issue(mock, area, .whenRequired)

        XCTAssertEqual(1, response.credentials.count)
        let encryptedRequest = await mock.seenEncryptedRequest
        XCTAssertFalse(encryptedRequest)
        let enc = await mock.seenResponseEnc
        XCTAssertNil(enc)
    }

    /// …but honours `encryption_required: true` without being asked.
    func testWhenRequiredEncryptsIfTheIssuerRequiresIt() async throws {
        let area = SoftwareSecureArea()
        let mock = try await issuer(area, supported: true, required: true)

        let response = try await issue(mock, area, .whenRequired)

        XCTAssertEqual(1, response.credentials.count)
        let encryptedRequest = await mock.seenEncryptedRequest
        XCTAssertTrue(encryptedRequest)
        let enc = await mock.seenResponseEnc
        XCTAssertEqual("A256GCM", enc)
    }

    func testRequiredFailsAgainstAnIssuerWithoutSupport() async throws {
        let area = SoftwareSecureArea()
        let mock = try await issuer(area, supported: false)

        do {
            _ = try await issue(mock, area, .required)
            XCTFail("required encryption must fail against a plaintext issuer")
        } catch VciError.metadata {}
    }

    /// A plaintext issuer stays plaintext under the default policy — no behaviour change.
    func testPlaintextIssuerIsUnaffected() async throws {
        let area = SoftwareSecureArea()
        let mock = try await issuer(area, supported: false)

        let response = try await issue(mock, area, .whenRequired)

        XCTAssertEqual(1, response.credentials.count)
        let encryptedRequest = await mock.seenEncryptedRequest
        XCTAssertFalse(encryptedRequest)
    }

    /// §10: the JWE `alg` must equal the chosen JWK's `alg`, and we only implement ECDH-ES.
    func testNegotiationRejectsAnIssuerWithoutEcdhEs() async throws {
        let meta = try CredentialIssuerMetadata.fromObj(try JsonValue.parse(#"""
        {"credential_issuer":"https://i.example","credential_endpoint":"https://i.example/c",
         "credential_response_encryption":{"alg_values_supported":["RSA-OAEP-256"],
           "enc_values_supported":["A128GCM"],"encryption_required":true}}
        """#))
        do {
            _ = try CredentialEncryptionSession.negotiate(.whenRequired, meta)
            XCTFail("RSA-OAEP is not implemented")
        } catch VciError.unsupported {}
    }

    /// §8.2: response encryption without a request-encryption key is not a conformant configuration.
    func testNegotiationRejectsResponseEncryptionWithoutRequestEncryption() async throws {
        let meta = try CredentialIssuerMetadata.fromObj(try JsonValue.parse(#"""
        {"credential_issuer":"https://i.example","credential_endpoint":"https://i.example/c",
         "credential_response_encryption":{"alg_values_supported":["ECDH-ES"],
           "enc_values_supported":["A128GCM"],"encryption_required":true}}
        """#))
        do {
            _ = try CredentialEncryptionSession.negotiate(.whenRequired, meta)
            XCTFail("§8.2 requires credential_request_encryption")
        } catch VciError.metadata {}
    }
}
