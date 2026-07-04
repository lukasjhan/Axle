import Foundation
import SdJwt
import XCTest
@testable import OpenID4VP

final class DcqlEngineTests: XCTestCase {

    private struct FakeCred: QueryableCredential {
        let credentialId: String
        let vct: String?
        let claims: JsonValue
        let format = "dc+sd-jwt"
        let docType: String? = nil
    }

    private func str(_ s: String) -> JsonValue { .str(s) }

    private var pid: FakeCred {
        FakeCred(credentialId: "pid-1", vct: "urn:eudi:pid:1", claims: .obj([
            ("family_name", .str("Han")),
            ("given_name", .str("Jongho")),
            ("nationalities", .arr([.str("LU"), .str("KR")])),
            ("address", .obj([("country", .str("LU")), ("locality", .str("Luxembourg"))])),
            ("age_over", .arr([.obj([("age", .numInt(18)), ("over", .bool(true))])])),
        ]))
    }

    private func query(_ json: String) throws -> DcqlQuery {
        try DcqlQuery.parse(try JsonValue.parse(json))
    }

    func testSimpleClaimMatch() throws {
        let q = try query(#"{"credentials":[{"id":"c","format":"dc+sd-jwt","meta":{"vct_values":["urn:eudi:pid:1"]},"claims":[{"path":["family_name"]},{"path":["given_name"]}]}]}"#)
        let r = DcqlEngine.match(q, held: [pid])
        XCTAssertTrue(r.isSatisfiable())
        let cand = r.candidatesByQuery["c"]!.first!
        XCTAssertEqual(Set([["family_name"], ["given_name"]]), Set(cand.disclosedPaths))
    }

    func testVctMismatchExcludes() throws {
        let q = try query(#"{"credentials":[{"id":"c","format":"dc+sd-jwt","meta":{"vct_values":["urn:other"]},"claims":[{"path":["family_name"]}]}]}"#)
        XCTAssertTrue(DcqlEngine.match(q, held: [pid]).candidatesByQuery["c"]!.isEmpty)
    }

    func testMissingClaimExcludes() throws {
        let q = try query(#"{"credentials":[{"id":"c","format":"dc+sd-jwt","claims":[{"path":["email"]}]}]}"#)
        XCTAssertTrue(DcqlEngine.match(q, held: [pid]).candidatesByQuery["c"]!.isEmpty)
    }

    func testNestedPath() throws {
        let q = try query(#"{"credentials":[{"id":"c","format":"dc+sd-jwt","claims":[{"path":["address","locality"]}]}]}"#)
        XCTAssertEqual([["address", "locality"]], DcqlEngine.match(q, held: [pid]).candidatesByQuery["c"]!.first!.disclosedPaths)
    }

    func testArrayIndexPath() throws {
        let q = try query(#"{"credentials":[{"id":"c","format":"dc+sd-jwt","claims":[{"path":["nationalities",0]}]}]}"#)
        XCTAssertEqual([["nationalities", "0"]], DcqlEngine.match(q, held: [pid]).candidatesByQuery["c"]!.first!.disclosedPaths)
    }

    func testNullWildcardOverArray() throws {
        let q = try query(#"{"credentials":[{"id":"c","format":"dc+sd-jwt","claims":[{"path":["nationalities",null]}]}]}"#)
        let cand = DcqlEngine.match(q, held: [pid]).candidatesByQuery["c"]!.first!
        XCTAssertEqual(Set([["nationalities", "0"], ["nationalities", "1"]]), Set(cand.disclosedPaths))
    }

    func testValuesMatchOnWildcard() throws {
        let q = try query(#"{"credentials":[{"id":"c","format":"dc+sd-jwt","claims":[{"path":["nationalities",null],"values":["KR"]}]}]}"#)
        XCTAssertEqual([["nationalities", "1"]], DcqlEngine.match(q, held: [pid]).candidatesByQuery["c"]!.first!.disclosedPaths)
    }

    func testValuesNoMatchExcludes() throws {
        let q = try query(#"{"credentials":[{"id":"c","format":"dc+sd-jwt","claims":[{"path":["nationalities",null],"values":["US"]}]}]}"#)
        XCTAssertTrue(DcqlEngine.match(q, held: [pid]).candidatesByQuery["c"]!.isEmpty)
    }

    func testNullWildcardValuesOnObjectArray() throws {
        let q = try query(#"{"credentials":[{"id":"c","format":"dc+sd-jwt","claims":[{"path":["age_over",null,"over"],"values":[true]}]}]}"#)
        XCTAssertEqual([["age_over", "0", "over"]], DcqlEngine.match(q, held: [pid]).candidatesByQuery["c"]!.first!.disclosedPaths)
    }

    func testClaimSetsChoosesFirstSatisfiable() throws {
        let q = try query(#"{"credentials":[{"id":"c","format":"dc+sd-jwt","claims":[{"id":"e","path":["email"]},{"id":"f","path":["family_name"]},{"id":"g","path":["given_name"]}],"claim_sets":[["e"],["f","g"]]}]}"#)
        let cand = DcqlEngine.match(q, held: [pid]).candidatesByQuery["c"]!.first!
        XCTAssertEqual(Set([["family_name"], ["given_name"]]), Set(cand.disclosedPaths))
    }

    func testCredentialSetsOptionalNotRequired() throws {
        let q = try query(#"{"credentials":[{"id":"pid","format":"dc+sd-jwt","claims":[{"path":["family_name"]}]},{"id":"mdl","format":"dc+sd-jwt","meta":{"vct_values":["urn:mdl"]},"claims":[{"path":["x"]}]}],"credential_sets":[{"options":[["pid"]],"required":true},{"options":[["mdl"]],"required":false}]}"#)
        let r = DcqlEngine.match(q, held: [pid])
        XCTAssertTrue(r.isSatisfiable())
        XCTAssertEqual(Set(["pid"]), r.requiredQueryIds)
    }

    func testCredentialSetsRequiredMissingUnsatisfiable() throws {
        let q = try query(#"{"credentials":[{"id":"mdl","format":"dc+sd-jwt","meta":{"vct_values":["urn:mdl"]},"claims":[{"path":["x"]}]}],"credential_sets":[{"options":[["mdl"]],"required":true}]}"#)
        XCTAssertFalse(DcqlEngine.match(q, held: [pid]).isSatisfiable())
    }
}
