import CborCose
import Foundation
import WalletAPI

public enum EnvelopeCodecError: Error {
    case malformed(String)
    case unsupportedVersion(Int64)
    case unknownFormat(Int64)
    case unknownLifecycle(Int64)
}

/// CredentialEnvelope <-> deterministic CBOR (integer-keyed maps, version field for migration).
/// Schema v1 — cross-language golden vector pinned in the tests (same bytes as Kotlin).
public enum EnvelopeCodec {

    private static let version: Int64 = 1

    // top-level keys
    private static let kVersion: Int64 = 0
    private static let kId: Int64 = 1
    private static let kFormatType: Int64 = 2      // 0 = mso_mdoc, 1 = dc+sd-jwt
    private static let kDocTypeOrVct: Int64 = 3
    private static let kCreatedAt: Int64 = 4       // epoch millis
    private static let kLifecycleType: Int64 = 5   // 0 pending, 1 deferred, 2 issued
    private static let kLifecycle: Int64 = 6
    private static let kMetadata: Int64 = 7        // optional issuer/display metadata

    public static func encode(_ envelope: CredentialEnvelope) throws -> [UInt8] {
        try CborEncoder.encode(toCbor(envelope))
    }

    public static func decode(_ bytes: [UInt8]) throws -> CredentialEnvelope {
        try fromCbor(try CborDecoder.decode(bytes))
    }

    private static func toCbor(_ e: CredentialEnvelope) -> Cbor {
        let formatType: Int64
        let docTypeOrVct: String
        switch e.format {
        case let .msoMdoc(docType):
            formatType = 0
            docTypeOrVct = docType
        case let .sdJwtVc(vct):
            formatType = 1
            docTypeOrVct = vct
        }

        let lifecycleType: Int64
        let lifecycle: Cbor
        switch e.lifecycle {
        case let .pending(authorizationUrl, resumeContext):
            lifecycleType = 0
            var m: [(Cbor, Cbor)] = []
            if let authorizationUrl { m.append((.int(0), .text(authorizationUrl))) }
            if let resumeContext { m.append((.int(1), .bytes(resumeContext))) }
            lifecycle = .map(m)
        case let .deferred(transactionContext, retryAfter):
            lifecycleType = 1
            var m: [(Cbor, Cbor)] = [(.int(0), .bytes(transactionContext))]
            if let retryAfter { m.append((.int(1), .int(epochMillis(retryAfter)))) }
            lifecycle = .map(m)
        case let .issued(policy, instances):
            lifecycleType = 2
            let policyMap = Cbor.map([
                (.int(0), .int(Int64(policy.batchSize))),
                (.int(1), .int(policy.use == .rotate ? 0 : 1)),
            ])
            let instanceArray = Cbor.array(instances.map { i in
                .map([
                    (.int(0), .text(i.key.secureArea.value)),
                    (.int(1), .text(i.key.alias)),
                    (.int(2), .bytes(i.payload)),
                    (.int(3), .int(Int64(i.useCount))),
                ])
            })
            lifecycle = .map([(.int(0), policyMap), (.int(1), instanceArray)])
        }

        var entries: [(Cbor, Cbor)] = [
            (.int(kVersion), .int(version)),
            (.int(kId), .text(e.id.value)),
            (.int(kFormatType), .int(formatType)),
            (.int(kDocTypeOrVct), .text(docTypeOrVct)),
            (.int(kCreatedAt), .int(epochMillis(e.createdAt))),
            (.int(kLifecycleType), .int(lifecycleType)),
            (.int(kLifecycle), lifecycle),
        ]
        if let m = e.metadata {
            var mm: [(Cbor, Cbor)] = [(.int(0), .text(m.issuerUrl))]
            if let x = m.issuerDisplayName { mm.append((.int(1), .text(x))) }
            mm.append((.int(2), .text(m.configurationId)))
            if let x = m.displayName { mm.append((.int(3), .text(x))) }
            if let x = m.logoUri { mm.append((.int(4), .text(x))) }
            if let x = m.backgroundColor { mm.append((.int(5), .text(x))) }
            if let x = m.issuerTrusted { mm.append((.int(6), .bool(x))) }
            if let x = m.issuerRegistered { mm.append((.int(7), .bool(x))) }
            entries.append((.int(kMetadata), .map(mm)))
        }
        return .map(entries)
    }

    private static func fromCbor(_ c: Cbor) throws -> CredentialEnvelope {
        let root = try asMap(c, "envelope")
        let v = try long(root, kVersion)
        guard v == version else { throw EnvelopeCodecError.unsupportedVersion(v) }

        let format: CredentialFormat
        switch try long(root, kFormatType) {
        case 0: format = .msoMdoc(docType: try text(root, kDocTypeOrVct))
        case 1: format = .sdJwtVc(vct: try text(root, kDocTypeOrVct))
        case let t: throw EnvelopeCodecError.unknownFormat(t)
        }

        guard let lifecycleCbor = get(root, kLifecycle) else {
            throw EnvelopeCodecError.malformed("missing lifecycle")
        }
        let lifecycleMap = try asMap(lifecycleCbor, "lifecycle")

        let lifecycle: EnvelopeLifecycle
        switch try long(root, kLifecycleType) {
        case 0:
            var url: String?
            if case let .text(s)? = get(lifecycleMap, 0) { url = s }
            var ctx: [UInt8]?
            if case let .bytes(b)? = get(lifecycleMap, 1) { ctx = b }
            lifecycle = .pending(authorizationUrl: url, resumeContext: ctx)
        case 1:
            var retryAfter: Date?
            if let r = get(lifecycleMap, 1) { retryAfter = date(try longValue(r, "retryAfter")) }
            lifecycle = .deferred(transactionContext: try bytes(lifecycleMap, 0), retryAfter: retryAfter)
        case 2:
            guard let policyCbor = get(lifecycleMap, 0) else {
                throw EnvelopeCodecError.malformed("missing policy")
            }
            let policyMap = try asMap(policyCbor, "policy")
            let policy = CredentialPolicy(
                batchSize: Int(try long(policyMap, 0)),
                use: try long(policyMap, 1) == 0 ? .rotate : .oneTime
            )
            guard case let .array(items)? = get(lifecycleMap, 1) else {
                throw EnvelopeCodecError.malformed("missing instances")
            }
            let instances = try items.map { item in
                let m = try asMap(item, "instance")
                return CredentialInstance(
                    key: KeyHandle(
                        secureArea: SecureAreaId(try text(m, 0)),
                        alias: try text(m, 1)
                    ),
                    payload: try bytes(m, 2),
                    useCount: Int(try long(m, 3))
                )
            }
            lifecycle = .issued(policy: policy, instances: instances)
        case let t:
            throw EnvelopeCodecError.unknownLifecycle(t)
        }

        var metadata: CredentialMetadata?
        if let mCbor = get(root, kMetadata) {
            let m = try asMap(mCbor, "metadata")
            func txt(_ key: Int64) -> String? { if case let .text(s)? = get(m, key) { return s }; return nil }
            func bl(_ key: Int64) -> Bool? { if case let .bool(b)? = get(m, key) { return b }; return nil }
            metadata = CredentialMetadata(
                issuerUrl: try text(m, 0),
                issuerDisplayName: txt(1),
                configurationId: try text(m, 2),
                displayName: txt(3),
                logoUri: txt(4),
                backgroundColor: txt(5),
                issuerTrusted: bl(6),
                issuerRegistered: bl(7)
            )
        }

        return CredentialEnvelope(
            id: CredentialId(try text(root, kId)),
            format: format,
            createdAt: date(try long(root, kCreatedAt)),
            lifecycle: lifecycle,
            metadata: metadata
        )
    }

    /* ---- helpers ---- */

    private static func epochMillis(_ d: Date) -> Int64 {
        Int64((d.timeIntervalSince1970 * 1000).rounded())
    }

    private static func date(_ millis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    private static func asMap(_ c: Cbor, _ what: String) throws -> [(Cbor, Cbor)] {
        guard case let .map(entries) = c else { throw EnvelopeCodecError.malformed("\(what) must be a map") }
        return entries
    }

    private static func get(_ map: [(Cbor, Cbor)], _ key: Int64) -> Cbor? {
        map.first { $0.0.asInt64 == key }?.1
    }

    private static func longValue(_ c: Cbor, _ what: String) throws -> Int64 {
        guard let v = c.asInt64 else { throw EnvelopeCodecError.malformed("\(what) must be an integer") }
        return v
    }

    private static func long(_ map: [(Cbor, Cbor)], _ key: Int64) throws -> Int64 {
        guard let c = get(map, key) else { throw EnvelopeCodecError.malformed("missing key \(key)") }
        return try longValue(c, "key \(key)")
    }

    private static func text(_ map: [(Cbor, Cbor)], _ key: Int64) throws -> String {
        guard case let .text(s)? = get(map, key) else { throw EnvelopeCodecError.malformed("missing text key \(key)") }
        return s
    }

    private static func bytes(_ map: [(Cbor, Cbor)], _ key: Int64) throws -> [UInt8] {
        guard case let .bytes(b)? = get(map, key) else { throw EnvelopeCodecError.malformed("missing bytes key \(key)") }
        return b
    }
}
