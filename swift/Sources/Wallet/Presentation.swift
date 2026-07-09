import Foundation
import OpenID4VP
import WalletAPI

/// A resolved verifier request, ready for the consent screen: who is asking, what they want, and which
/// stored credentials can satisfy each query. The raw resolved request + match are carried for respond.
public struct PresentationRequest {
    public let verifier: VerifierInfo
    public let queries: [QueryPresentation]
    public let transactionData: [String]?
    public let satisfiable: Bool
    let resolved: ResolvedRequest
    let matches: DcqlMatchResult
}

/// Who is requesting, and whether trust was established (signed request verified to a reader anchor).
public struct VerifierInfo {
    public let clientId: String
    public let clientIdScheme: String
    public let commonName: String?
    public let trusted: Bool
}

/// One DCQL query with the stored credentials that can answer it.
public struct QueryPresentation {
    public let queryId: String
    public let required: Bool
    public let candidates: [PresentationCandidate]
    /// §6.1 `multiple`: whether the verifier accepts more than one credential for this query.
    public let multiple: Bool

    public init(queryId: String, required: Bool, candidates: [PresentationCandidate], multiple: Bool = false) {
        self.queryId = queryId; self.required = required; self.candidates = candidates; self.multiple = multiple
    }
}

/// A stored credential that satisfies a query, with the claim paths it would disclose.
public struct PresentationCandidate {
    public let credentialId: CredentialId
    public let disclosedPaths: [[String]]
}

/// The user's choice of which credential(s) answer each query. A `multiple: false` query takes exactly one
/// credential; a `multiple: true` query (§6.1) may take several.
public struct PresentationSelection {
    public let chosen: [String: [CredentialId]]
    public init(chosen: [String: [CredentialId]]) { self.chosen = chosen }

    /// Auto-pick: all candidates for a `multiple` query, else the first candidate, for every required query.
    public static func auto(_ request: PresentationRequest) -> PresentationSelection {
        var chosen: [String: [CredentialId]] = [:]
        for query in request.queries where query.required && !query.candidates.isEmpty {
            chosen[query.queryId] = query.multiple ? query.candidates.map { $0.credentialId } : [query.candidates[0].credentialId]
        }
        return PresentationSelection(chosen: chosen)
    }
}

/// Presentation session state.
public enum PresentationState {
    case resolvingRequest
    case requestResolved(PresentationRequest)
    case submitting
    /// Success. `redirectUri` is the verifier redirect for the remote (URL/QR) flow; `dcApiResponse` is
    /// the JSON object to hand back to the platform for the Digital Credentials API flow. Exactly one is set.
    case completed(redirectUri: String?, dcApiResponse: String?)
    /// The user refused. For the remote flow the wallet has told the verifier (`access_denied`, §8.5);
    /// `redirectUri` is the URI the verifier asked the wallet to send the user agent to, if any.
    case declined(redirectUri: String?)
    case failed(PresentationError)

    public var isTerminal: Bool {
        switch self {
        case .completed, .declined, .failed: return true
        default: return false
        }
    }
}
