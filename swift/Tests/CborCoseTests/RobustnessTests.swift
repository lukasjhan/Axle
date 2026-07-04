import XCTest
@testable import CborCose

/// Anti-happy-path evidence: random structural fuzz, deep nesting, byte-level truncation.
final class RobustnessTests: XCTestCase {

    private var seed: UInt64 = 0x0123_4567_89AB_CDEF

    private func rnd(_ bound: Int) -> Int {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((seed >> 33) % UInt64(bound))
    }

    private func randomValue(_ depth: Int) -> Cbor {
        switch rnd(depth > 0 ? 9 : 6) {
        case 0: return .int(Int64(rnd(1_000_000) - 500_000))
        case 1: return .uint(UInt64.max - UInt64(rnd(1000)))
        case 2: return .text("s\(rnd(1000))-ü水\"\\\n\(rnd(10))")
        case 3: return .bytes((0..<rnd(20)).map { _ in UInt8(rnd(256)) })
        case 4:
            let simples: [Cbor] = [.bool(true), .bool(false), .null, .undefined, .simple(99)]
            return simples[rnd(5)]
        case 5:
            let doubles: [Double] = [0.0, -0.0, 1.5, 1.1, 65504.0, 1e300, .nan, .infinity]
            return .fp(doubles[rnd(8)])
        case 6: return .array((0..<rnd(4)).map { _ in randomValue(depth - 1) })
        case 7: return .map((0..<rnd(4)).map { i in (.text("k\(i)-\(rnd(100))"), randomValue(depth - 1)) })
        default: return .tagged(UInt64(rnd(1000)), randomValue(depth - 1))
        }
    }

    func testRandomTreesReachCanonicalFixpoint() throws {
        for i in 0..<300 {
            let value = randomValue(5)
            let encoded = try CborEncoder.encode(value)
            let decoded = try CborDecoder.decode(encoded)
            XCTAssertEqual(encoded, try CborEncoder.encode(decoded), "iteration \(i)")
        }
    }

    func testDeepNestingRoundtripsAndGuardHolds() throws {
        var value = Cbor.int(7)
        for _ in 0..<200 { value = .array([value]) }
        XCTAssertEqual(value, try CborDecoder.decode(try CborEncoder.encode(value)))

        let tooDeep = [UInt8](repeating: 0x81, count: 600) + [0x00]
        XCTAssertThrowsError(try CborDecoder.decode(tooDeep))
    }

    func testEveryTruncationThrowsCleanly() throws {
        let bytes = try CborEncoder.encode(randomValue(4))
        for len in 0..<bytes.count {
            XCTAssertThrowsError(
                try CborDecoder.decode(Array(bytes[0..<len]), strict: false),
                "prefix length \(len)"
            )
        }
    }
}
