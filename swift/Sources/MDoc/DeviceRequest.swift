import CborCose
import Foundation

/// A data element a reader asks for (ISO 18013-5 §8.3.2.1.2.1).
public struct RequestedElement {
    public let identifier: String
    public let intentToRetain: Bool
}

/// One document request: the requested docType + elements, plus the reader's optional signature.
public struct DocRequest {
    public let docType: String
    /// namespace -> requested elements (in wire order).
    public let requested: [(String, [RequestedElement])]
    /// The `ItemsRequestBytes` (#6.24) as received — needed to reconstruct `ReaderAuthentication`.
    public let itemsRequestBytes: Cbor
    public let readerAuth: CoseSign1?

    /// The requested elements flagged `IntentToRetain` (ISO 18013-5 §8.3.2.1.2.1): namespace -> element
    /// identifiers the reader declared it will keep beyond the transaction. Namespaces with nothing retained
    /// are omitted. Surfaced so a holder can put the declaration in front of the user before consenting.
    public func retained() -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (ns, elems) in requested {
            let retained = elems.filter(\.intentToRetain).map(\.identifier)
            if !retained.isEmpty { out[ns] = retained }
        }
        return out
    }

    /// The element identifiers to disclose from `issuerSigned` for this request: the requested elements the
    /// mdoc actually holds, with `age_over_NN` resolved per `AgeAttestation` (ISO 18013-5 §7.2.5) rather than
    /// matched literally — so `age_over_18` can be answered by a held `age_over_21: true`, and a held
    /// `age_over_16: true` does *not* answer it.
    public func disclosable(_ issuerSigned: IssuerSigned) -> [String: [String]] {
        let held = issuerSigned.elements()
        var out: [String: [String]] = [:]
        for (ns, elems) in requested {
            let heldNs = Dictionary(held.first { $0.0 == ns }?.1 ?? [], uniquingKeysWith: { first, _ in first })
            var disclosable: [String] = []
            for element in elems {
                // §7.2.5 governs age attestations; everything else is a literal "do you hold this element".
                // A malformed attestation (non-boolean value) falls back to the literal match.
                let literal = heldNs[element.identifier] != nil ? element.identifier : nil
                let resolved = AgeAttestation.age(of: element.identifier)
                    .flatMap { AgeAttestation.resolve(requestedAge: $0, held: heldNs) } ?? literal
                // two age_over_NN requests can resolve to the same attestation
                if let resolved, !disclosable.contains(resolved) { disclosable.append(resolved) }
            }
            if !disclosable.isEmpty { out[ns] = disclosable }
        }
        return out
    }
}

/// A reader's `DeviceRequest` (ISO 18013-5 §8.3.2.1.2.1): the documents + elements it wants.
public struct DeviceRequest {
    public let version: String
    public let docRequests: [DocRequest]

    public func docRequest(for docType: String) -> DocRequest? { docRequests.first { $0.docType == docType } }

    public static func decode(_ bytes: [UInt8]) throws -> DeviceRequest {
        guard case let .map(entries) = try CborDecoder.decode(bytes) else { throw MdocError("DeviceRequest must be a map") }
        guard case let .text(version)? = mdocField(entries, "version") else { throw MdocError("missing version") }
        guard case let .array(drs)? = mdocField(entries, "docRequests") else { throw MdocError("missing docRequests") }

        let docRequests: [DocRequest] = try drs.map { dr in
            guard case let .map(drMap) = dr else { throw MdocError("docRequest must be a map") }
            guard case let .tagged(_, inner)? = mdocField(drMap, "itemsRequest"), case let .bytes(innerBytes) = inner else {
                throw MdocError("missing itemsRequest")
            }
            let itemsRequestBytes = mdocField(drMap, "itemsRequest")!
            guard case let .map(itemsRequest) = try CborDecoder.decode(innerBytes) else { throw MdocError("ItemsRequest must be a map") }
            guard case let .text(docType)? = mdocField(itemsRequest, "docType") else { throw MdocError("missing docType") }
            guard case let .map(nsMap)? = mdocField(itemsRequest, "nameSpaces") else { throw MdocError("missing nameSpaces") }

            let requested: [(String, [RequestedElement])] = try nsMap.map { nsEntry in
                guard case let .text(ns) = nsEntry.0, case let .map(elems) = nsEntry.1 else { throw MdocError("bad nameSpaces") }
                let els: [RequestedElement] = try elems.map { el in
                    guard case let .text(id) = el.0 else { throw MdocError("element id must be text") }
                    var intent = false
                    if case let .bool(b) = el.1 { intent = b }
                    return RequestedElement(identifier: id, intentToRetain: intent)
                }
                return (ns, els)
            }
            var readerAuth: CoseSign1?
            if let ra = mdocField(drMap, "readerAuth") { readerAuth = try CoseSign1.fromCbor(ra) }
            return DocRequest(docType: docType, requested: requested, itemsRequestBytes: itemsRequestBytes, readerAuth: readerAuth)
        }
        return DeviceRequest(version: version, docRequests: docRequests)
    }
}

func mdocField(_ entries: [(Cbor, Cbor)], _ name: String) -> Cbor? {
    entries.first { if case let .text(t) = $0.0 { return t == name }; return false }?.1
}

/// Resolves + trusts a reader's key from the `readerAuth` x5chain (implemented by the `Trust` module).
public protocol MdocReaderTrust: Sendable {
    func readerKey(x5chain: [[UInt8]]) async throws -> EcPublicKey
}

/// Outcome of reader authentication (ISO 18013-5 §9.1.4).
public struct ReaderInfo {
    public let trusted: Bool
    public let certificateChain: [[UInt8]]?
}

/// Verifies a reader's `readerAuth` (ISO 18013-5 §9.1.4): a COSE_Sign1 over
/// `ReaderAuthentication = ["ReaderAuthentication", SessionTranscript, ItemsRequestBytes]`
/// (detached payload), authenticating *who is asking* against a reader trust anchor.
public enum ReaderAuth {

    public static func verify(_ docRequest: DocRequest, sessionTranscript: Cbor, trust: any MdocReaderTrust) async throws -> ReaderInfo {
        guard let readerAuth = docRequest.readerAuth else { throw MdocError("docRequest has no readerAuth") }
        guard let x5chain = (try? readerAuth.protectedHeaders())?.x5chain ?? readerAuth.unprotected.x5chain else {
            throw MdocError("readerAuth has no x5chain")
        }
        let key = try await trust.readerKey(x5chain: x5chain) // validates the reader chain (throws if untrusted)

        let readerAuthentication = Cbor.array([.text("ReaderAuthentication"), sessionTranscript, docRequest.itemsRequestBytes])
        let readerAuthBytes = try CborEncoder.encode(.tagged(TAG_ENCODED_CBOR, .bytes(try CborEncoder.encode(readerAuthentication))))
        guard readerAuth.verify(publicKey: key, detachedPayload: readerAuthBytes) else { throw MdocError("readerAuth signature invalid") }
        return ReaderInfo(trusted: true, certificateChain: x5chain)
    }
}
