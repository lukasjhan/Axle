import CborCose
import MDoc

/// Reader-side helpers that keep the `MDoc` / `CborCose` types out of the app: the app builds a request and
/// renders results through these, naming only `AppleProximity` types. Mirrors the android demo's
/// `readerRequest()` + `ReaderResultCard` rendering.

/// One document a proximity reader received, flattened for display.
public struct ReaderResultDoc: Sendable {
    public let docType: String
    public let deviceAuthenticated: Bool
    public let claims: [Claim]

    public struct Claim: Sendable {
        public let namespace: String
        public let element: String
        public let value: String
    }
}

public enum MdocReaderRequests {
    /// The default PID request (android demo `readerRequest()`): PID doctype + core identity elements.
    public static func pid() -> [RequestedDocument] {
        [RequestedDocument(
            docType: "eu.europa.ec.eudi.pid.1",
            elements: [("eu.europa.ec.eudi.pid.1", ["family_name", "given_name", "birth_date", "nationality"])]
        )]
    }

    /// Flattens verified documents into display rows, rendering each CBOR element value to a readable string.
    public static func flatten(_ documents: [VerifiedDocument]) -> [ReaderResultDoc] {
        documents.map { doc in
            var claims: [ReaderResultDoc.Claim] = []
            for (namespace, elements) in doc.elements {
                for (element, value) in elements {
                    claims.append(.init(namespace: namespace, element: element, value: cborString(value)))
                }
            }
            return ReaderResultDoc(
                docType: doc.docType,
                deviceAuthenticated: doc.deviceAuthenticated,
                claims: claims.sorted { $0.element < $1.element }
            )
        }
    }
}

/// Best-effort human rendering of a CBOR element value (dates unwrapped from their tag).
func cborString(_ value: Cbor) -> String {
    switch value {
    case let .text(s): return s
    case let .uint(u): return String(u)
    case let .bool(b): return b ? "Yes" : "No"
    case let .bytes(b): return "\(b.count) bytes"
    case let .array(a): return a.map(cborString).joined(separator: ", ")
    case let .tagged(_, inner): return cborString(inner)
    case .null: return "—"
    default: return String(describing: value)
    }
}
