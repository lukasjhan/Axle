import CborCose
import Foundation
import WalletAPI
import WalletTestKit
import XCTest
@testable import MDoc

/// ISO/IEC 18013-5 §7.2.5 — "Age attestation: nearest 'true' attestation above request".
final class AgeAttestationTests: XCTestCase {

    private let docType = "org.iso.18013.5.1.mDL"
    private let namespace = "org.iso.18013.5.1"

    private func held(_ attestations: [(Int, Bool)]) -> [String: Cbor] {
        Dictionary(uniqueKeysWithValues: attestations.map { (String(format: "age_over_%02d", $0.0), Cbor.bool($0.1)) })
    }

    func testParsesTwoDigitIdentifiersOnly() {
        XCTAssertEqual(18, AgeAttestation.age(of: "age_over_18"))
        XCTAssertEqual(0, AgeAttestation.age(of: "age_over_00"))
        XCTAssertEqual(99, AgeAttestation.age(of: "age_over_99"))
        XCTAssertNil(AgeAttestation.age(of: "age_over_8")) // §7.2.5: NN is 00-99, two digits
        XCTAssertNil(AgeAttestation.age(of: "age_over_180"))
        XCTAssertNil(AgeAttestation.age(of: "age_over_ab"))
        XCTAssertNil(AgeAttestation.age(of: "age_in_years"))
        XCTAssertNil(AgeAttestation.age(of: "birth_date"))
    }

    /// Step 1: among TRUE attestations with nn >= NN, the smallest difference wins.
    func testStep1PicksNearestTrueAtOrAboveRequest() {
        let mdl = held([(16, true), (18, true), (21, true), (25, false)])
        XCTAssertEqual("age_over_21", AgeAttestation.resolve(requestedAge: 21, held: mdl))
        XCTAssertEqual("age_over_18", AgeAttestation.resolve(requestedAge: 18, held: mdl))
        XCTAssertEqual("age_over_16", AgeAttestation.resolve(requestedAge: 16, held: mdl))
        // Nothing held at exactly 20 — the nearest TRUE above it answers "are you over 20?" just as well.
        XCTAssertEqual("age_over_21", AgeAttestation.resolve(requestedAge: 20, held: mdl))
        XCTAssertEqual("age_over_18", AgeAttestation.resolve(requestedAge: 17, held: mdl))
    }

    /// Step 2: no TRUE at/above the request, so the nearest FALSE at/below it answers instead.
    func testStep2FallsBackToNearestFalseAtOrBelowRequest() {
        let minor = held([(13, true), (16, false), (18, false), (21, false)])
        XCTAssertEqual("age_over_18", AgeAttestation.resolve(requestedAge: 18, held: minor))
        XCTAssertEqual("age_over_16", AgeAttestation.resolve(requestedAge: 17, held: minor)) // nearest FALSE <= 17
        XCTAssertEqual("age_over_18", AgeAttestation.resolve(requestedAge: 20, held: minor))
        XCTAssertEqual("age_over_13", AgeAttestation.resolve(requestedAge: 13, held: minor)) // TRUE exact hit wins step 1
    }

    /// Step 3: neither branch produces an answer, so no age element is returned at all.
    func testStep3ReturnsNothingWhenNeitherBranchMatches() {
        // "over 25 is false" does not answer "are you over 18?" — and there is no TRUE at or above 18.
        XCTAssertNil(AgeAttestation.resolve(requestedAge: 18, held: held([(25, false)])))
        XCTAssertNil(AgeAttestation.resolve(requestedAge: 18, held: [:]))
        // A TRUE strictly below the request is not an answer either.
        XCTAssertNil(AgeAttestation.resolve(requestedAge: 21, held: held([(18, true)])))
    }

    /// Only booleans are attestations; a malformed value must not be picked as an answer.
    func testIgnoresNonBooleanValues() {
        XCTAssertNil(AgeAttestation.resolve(requestedAge: 18, held: ["age_over_18": .text("true")]))
    }

    // MARK: - end-to-end through DocRequest.disclosable

    private func mdoc(_ elements: [(String, Cbor)]) async throws -> IssuerSigned {
        let area = SoftwareSecureArea()
        let issuerKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let deviceKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let bytes = try await MdocTestIssuer.issue(
            area: area, issuerKey: issuerKey, deviceKey: deviceKey.publicKey,
            docType: docType, namespace: namespace, elements: elements,
            x5chain: [[0x30, 0x01]],
            signed: MdocTestIssuer.isoFormatter.date(from: "2026-01-01T00:00:00Z")!,
            validFrom: MdocTestIssuer.isoFormatter.date(from: "2026-01-01T00:00:00Z")!,
            validUntil: MdocTestIssuer.isoFormatter.date(from: "2027-01-01T00:00:00Z")!)
        return try IssuerSigned.decode(bytes)
    }

    private func docRequest(_ elements: [String]) -> DocRequest {
        DocRequest(docType: docType,
                   requested: [(namespace, elements.map { RequestedElement(identifier: $0, intentToRetain: false) })],
                   itemsRequestBytes: .null, readerAuth: nil)
    }

    /// A request the mdoc cannot answer literally is still answered by the nearest attestation above it.
    func testDisclosableSubstitutesTheNearestAttestation() async throws {
        let issuerSigned = try await mdoc([("family_name", .text("Han")), ("age_over_18", .bool(true)), ("age_over_21", .bool(true))])
        // Asked for age_over_20, which this mDL does not carry — age_over_21: true answers it (§7.2.5 step 1).
        XCTAssertEqual(["age_over_21"], docRequest(["age_over_20"]).disclosable(issuerSigned)[namespace])
        XCTAssertEqual(["family_name", "age_over_18"], docRequest(["family_name", "age_over_18"]).disclosable(issuerSigned)[namespace])
    }

    /// Two requests resolving to the same attestation disclose it once, not twice.
    func testDisclosableDeduplicatesResolvedAttestations() async throws {
        let issuerSigned = try await mdoc([("age_over_21", .bool(true))])
        XCTAssertEqual(["age_over_21"], docRequest(["age_over_18", "age_over_20"]).disclosable(issuerSigned)[namespace])
    }

    /// Step 3 through the request path: the namespace drops out rather than disclosing a wrong answer.
    func testDisclosableOmitsUnanswerableAgeRequests() async throws {
        let issuerSigned = try await mdoc([("age_over_16", .bool(true))])
        XCTAssertNil(docRequest(["age_over_21"]).disclosable(issuerSigned)[namespace])
    }

    /// Non-age elements keep their literal matching — substitution is scoped to age attestations.
    func testDisclosableLeavesOtherElementsLiteral() async throws {
        let issuerSigned = try await mdoc([("family_name", .text("Han")), ("age_over_18", .bool(true))])
        XCTAssertEqual(["family_name"], docRequest(["family_name", "given_name"]).disclosable(issuerSigned)[namespace])
    }

    /// §7.2.5: "an mDL reader shall not request more than two age_over_NN data elements".
    func testReaderRejectsMoreThanTwoAgeRequests() async throws {
        let reader = MdocReader()
        let ladder = RequestedDocument(docType: docType, elements: [(namespace, ["age_over_16", "age_over_18", "age_over_21"])])
        do {
            _ = try await reader.buildDeviceRequest([ladder], sessionTranscript: .null)
            XCTFail("expected §7.2.5 to reject three age_over_NN elements")
        } catch {}

        // Two is the cap, not an error.
        let allowed = RequestedDocument(docType: docType, elements: [(namespace, ["age_over_18", "age_over_21", "family_name"])])
        _ = try await reader.buildDeviceRequest([allowed], sessionTranscript: .null)
    }
}
