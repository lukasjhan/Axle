import Foundation

/// Typed OpenID4VP errors.
public enum VpError: Error, CustomStringConvertible {
    case invalidRequest(String)
    case verifierNotTrusted(String)
    case queryNotSatisfiable(missing: Set<String>)
    case selectionIncomplete(String)
    case responseFailed(String)
    case unsupported(String)

    public var description: String {
        switch self {
        case let .invalidRequest(m): return "invalid request: \(m)"
        case let .verifierNotTrusted(m): return "verifier not trusted: \(m)"
        case let .queryNotSatisfiable(missing): return "DCQL query not satisfiable; missing: \(missing)"
        case let .selectionIncomplete(m): return "selection incomplete: \(m)"
        case let .responseFailed(m): return "response failed: \(m)"
        case let .unsupported(m): return "unsupported: \(m)"
        }
    }
}
