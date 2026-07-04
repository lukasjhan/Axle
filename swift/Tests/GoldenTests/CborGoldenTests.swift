import CborCose
import SdJwt
import XCTest

/// Cross-language golden vectors for deterministic CBOR (RFC 8949) — the identical `vectors/` file
/// is consumed by the Kotlin suite, so both implementations are byte-for-byte locked.
final class CborGoldenTests: XCTestCase {

    func testDeterministicEncodingMatchesGolden() throws {
        let root = try GoldenVectors.load("cbor/deterministic.json")
        guard case let .obj(o) = root, case let .arr(vectors)? = o.first(where: { $0.0 == "vectors" })?.1 else {
            return XCTFail("bad vectors file")
        }
        XCTAssertGreaterThanOrEqual(vectors.count, 20)
        for v in vectors {
            guard case let .obj(fields) = v,
                  case let .str(name)? = fields.first(where: { $0.0 == "name" })?.1,
                  case let .str(expected)? = fields.first(where: { $0.0 == "hex" })?.1,
                  let cborSpec = fields.first(where: { $0.0 == "cbor" })?.1 else { return XCTFail("bad vector") }

            let cbor = try GoldenVectors.buildCbor(cborSpec)
            XCTAssertEqual(expected, GoldenVectors.toHex(try CborEncoder.encode(cbor)), "encode '\(name)'")
            let reEncoded = GoldenVectors.toHex(try CborEncoder.encode(try CborDecoder.decode(GoldenVectors.hexToBytes(expected))))
            XCTAssertEqual(expected, reEncoded, "decode+re-encode '\(name)'")
        }
    }
}
