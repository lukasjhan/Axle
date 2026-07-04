import Foundation
import WalletAPI
import WalletTestKit
import XCTest
@testable import CredentialStore

private let goldenIssuedHex =
    "a700010166637265642d310201036e75726e3a657564693a7069643a31041b0000018bcfe56800050206a200a2000201010182"
    + "a40068736f66747761726501656b65792d31024201020300a40068736f66747761726501656b65792d32024203040301"

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

final class EnvelopeCodecTests: XCTestCase {

    private func sampleIssued() -> CredentialEnvelope {
        CredentialEnvelope(
            id: CredentialId("cred-1"),
            format: .sdJwtVc(vct: "urn:eudi:pid:1"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lifecycle: .issued(
                policy: CredentialPolicy(batchSize: 2, use: .oneTime),
                instances: [
                    CredentialInstance(key: KeyHandle(secureArea: SecureAreaId("software"), alias: "key-1"), payload: [1, 2], useCount: 0),
                    CredentialInstance(key: KeyHandle(secureArea: SecureAreaId("software"), alias: "key-2"), payload: [3, 4], useCount: 1),
                ]
            )
        )
    }

    func testIssuedGoldenRoundtripAndDeterminism() throws {
        let encoded = try EnvelopeCodec.encode(sampleIssued())
        XCTAssertEqual(goldenIssuedHex, hex(encoded), "cross-language golden vector (same constant in Kotlin EnvelopeCodecTest)")
        XCTAssertEqual(encoded, try EnvelopeCodec.encode(sampleIssued()), "encoding must be deterministic")
        XCTAssertEqual(encoded, try EnvelopeCodec.encode(try EnvelopeCodec.decode(encoded)), "decode/encode stable")

        let decoded = try EnvelopeCodec.decode(encoded)
        XCTAssertEqual("cred-1", decoded.id.value)
        XCTAssertEqual(CredentialFormat.sdJwtVc(vct: "urn:eudi:pid:1"), decoded.format)
        XCTAssertEqual(1_700_000_000_000, Int64((decoded.createdAt.timeIntervalSince1970 * 1000).rounded()))
        guard case let .issued(policy, instances) = decoded.lifecycle else { return XCTFail("expected issued") }
        XCTAssertEqual(CredentialPolicy(batchSize: 2, use: .oneTime), policy)
        XCTAssertEqual(2, instances.count)
        XCTAssertEqual("key-1", instances[0].key.alias)
        XCTAssertEqual([1, 2], instances[0].payload)
        XCTAssertEqual(1, instances[1].useCount)
    }

    func testPendingRoundtrip() throws {
        let envelope = CredentialEnvelope(
            id: CredentialId("cred-2"),
            format: .msoMdoc(docType: "org.iso.18013.5.1.mDL"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.001),
            lifecycle: .pending(authorizationUrl: "https://issuer.example/authorize", resumeContext: [9])
        )
        let decoded = try EnvelopeCodec.decode(try EnvelopeCodec.encode(envelope))
        guard case let .pending(url, ctx) = decoded.lifecycle else { return XCTFail("expected pending") }
        XCTAssertEqual("https://issuer.example/authorize", url)
        XCTAssertEqual([9], ctx)
    }

    func testDeferredRoundtripWithAbsentOptionals() throws {
        let envelope = CredentialEnvelope(
            id: CredentialId("cred-3"),
            format: .msoMdoc(docType: "eu.europa.ec.eudi.pid.1"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.002),
            lifecycle: .deferred(transactionContext: [7, 7], retryAfter: nil)
        )
        let decoded = try EnvelopeCodec.decode(try EnvelopeCodec.encode(envelope))
        guard case let .deferred(ctx, retryAfter) = decoded.lifecycle else { return XCTFail("expected deferred") }
        XCTAssertEqual([7, 7], ctx)
        XCTAssertNil(retryAfter)
    }
}

final class DefaultCredentialStoreTests: XCTestCase {

    private func issued(_ id: String, use: KeyUse, batch: Int) -> CredentialEnvelope {
        CredentialEnvelope(
            id: CredentialId(id),
            format: .sdJwtVc(vct: "urn:eudi:pid:1"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lifecycle: .issued(
                policy: CredentialPolicy(batchSize: batch, use: use),
                instances: (1...batch).map {
                    CredentialInstance(key: KeyHandle(secureArea: SecureAreaId("software"), alias: "key-\($0)"), payload: [UInt8($0)])
                }
            )
        )
    }

    func testCrudEmitsChanges() async throws {
        let store = DefaultCredentialStore(driver: InMemoryStorageDriver())
        let stream = await store.changes()
        var iterator = stream.makeAsyncIterator()

        try await store.save(issued("a", use: .rotate, batch: 1))
        try await store.save(issued("a", use: .rotate, batch: 1))
        try await store.delete(CredentialId("a"))

        let first = await iterator.next()
        let second = await iterator.next()
        let third = await iterator.next()
        XCTAssertEqual(first, .added(CredentialId("a")))
        XCTAssertEqual(second, .updated(CredentialId("a")))
        XCTAssertEqual(third, .removed(CredentialId("a")))

        let missing = try await store.get(CredentialId("a"))
        XCTAssertNil(missing)
        let all = try await store.list()
        XCTAssertTrue(all.isEmpty)
    }

    func testRotatePolicyCyclesLeastUsedInstance() async throws {
        let store = DefaultCredentialStore(driver: InMemoryStorageDriver())
        try await store.save(issued("r", use: .rotate, batch: 2))

        let first = try await store.consumeInstance(CredentialId("r"))
        XCTAssertEqual("key-1", first?.instance.key.alias)
        XCTAssertEqual(2, first?.remaining)

        let second = try await store.consumeInstance(CredentialId("r"))
        XCTAssertEqual("key-2", second?.instance.key.alias, "rotate must pick the least-used instance")

        let third = try await store.consumeInstance(CredentialId("r"))
        XCTAssertEqual("key-1", third?.instance.key.alias)

        guard case let .issued(_, instances)? = try await store.get(CredentialId("r"))?.lifecycle else {
            return XCTFail("expected issued")
        }
        XCTAssertEqual([2, 1], instances.map(\.useCount))
    }

    func testOneTimePolicyDepletesInstances() async throws {
        let store = DefaultCredentialStore(driver: InMemoryStorageDriver())
        try await store.save(issued("o", use: .oneTime, batch: 2))

        let first = try await store.consumeInstance(CredentialId("o"))
        XCTAssertEqual(1, first?.remaining)
        let second = try await store.consumeInstance(CredentialId("o"))
        XCTAssertEqual(0, second?.remaining)
        let third = try await store.consumeInstance(CredentialId("o"))
        XCTAssertNil(third, "exhausted one-time credential must return nil")

        guard case let .issued(_, instances)? = try await store.get(CredentialId("o"))?.lifecycle else {
            return XCTFail("expected issued")
        }
        XCTAssertTrue(instances.isEmpty, "envelope remains for re-issuance bookkeeping")
    }

    func testConsumeOnNonIssuedReturnsNil() async throws {
        let store = DefaultCredentialStore(driver: InMemoryStorageDriver())
        try await store.save(
            CredentialEnvelope(
                id: CredentialId("p"),
                format: .msoMdoc(docType: "mdl"),
                createdAt: Date(timeIntervalSince1970: 0),
                lifecycle: .pending(authorizationUrl: nil, resumeContext: nil)
            )
        )
        let pending = try await store.consumeInstance(CredentialId("p"))
        XCTAssertNil(pending)
        let missing = try await store.consumeInstance(CredentialId("missing"))
        XCTAssertNil(missing)
    }
}
