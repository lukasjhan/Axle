import XCTest
@testable import SdJwt

/// Anti-happy-path evidence for the JSON layer: fuzz roundtrips, deep nesting, truncation.
final class JsonRobustnessTests: XCTestCase {

    private var seed: UInt64 = 0x0FED_CBA9_8765_4321

    private func rnd(_ bound: Int) -> Int {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((seed >> 33) % UInt64(bound))
    }

    private func randomJson(_ depth: Int) -> JsonValue {
        switch rnd(depth > 0 ? 8 : 6) {
        case 0: return .numInt(Int64(rnd(2_000_000) - 1_000_000))
        case 1: return .numInt(9_007_199_254_740_991 + Int64(rnd(1000))) // beyond double precision
        case 2: return .str("s\(rnd(1000)) ü水\"\\\n\t\u{01}\(rnd(10))")
        case 3:
            let simples: [JsonValue] = [.bool(true), .bool(false), .null]
            return simples[rnd(3)]
        case 4:
            let doubles: [Double] = [1.5, -2.25, 3.141592653589793, 1e100]
            return .numDouble(doubles[rnd(4)])
        case 5: return .str("")
        case 6: return .arr((0..<rnd(4)).map { _ in randomJson(depth - 1) })
        default: return .obj((0..<rnd(4)).map { i in ("k\(i)", randomJson(depth - 1)) })
        }
    }

    func testRandomTreesRoundtrip() throws {
        for i in 0..<300 {
            let value = randomJson(5)
            XCTAssertEqual(value, try JsonValue.parse(value.serialize()), "iteration \(i)")
        }
    }

    func testDeepNestingRoundtripsAndGuardHolds() throws {
        var value = JsonValue.numInt(7)
        for _ in 0..<200 { value = .arr([value]) }
        XCTAssertEqual(value, try JsonValue.parse(value.serialize()))

        let tooDeep = String(repeating: "[", count: 300) + "0" + String(repeating: "]", count: 300)
        XCTAssertThrowsError(try JsonValue.parse(tooDeep))
    }

    func testEveryTruncationThrowsCleanly() throws {
        let doc = JsonValue.obj([
            ("a", randomJson(3)),
            ("s", .str("br{ce\"s}and\\escapes")),
            ("n", .arr([.numInt(123456), .numDouble(1.5)])),
        ]).serialize()
        let chars = Array(doc)
        for len in 0..<chars.count {
            XCTAssertThrowsError(try JsonValue.parse(String(chars[0..<len])), "prefix length \(len)")
        }
    }
}
