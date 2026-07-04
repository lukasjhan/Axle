import Foundation

/// Per-query consent data: which held credentials can answer it and what each would disclose.
public struct QueryPresentation {
    public let queryId: String
    public let required: Bool
    public let candidates: [CandidateMatch]
}

/// Everything the app needs to render the consent screen — immutable, not a UI model.
public struct PresentationRequest {
    public let verifier: VerifierInfo
    public let queries: [QueryPresentation]
    public let transactionData: [String]?
    public let satisfiable: Bool
}

public enum PresentationState {
    case resolvingRequest
    case requestResolved(PresentationRequest)
    case submitting
    case completed(redirectUri: String?)
    case declined
    case failed(VpError)
}

/// Drives a single OpenID4VP remote presentation (API-CONTRACT §6.3).
public actor PresentationSession {
    private let client: Openid4VpClient
    private let held: [HeldSdJwtVc]

    public private(set) var state: PresentationState = .resolvingRequest

    private var resolved: ResolvedRequest?
    private var matches: DcqlMatchResult?

    public init(client: Openid4VpClient, held: [HeldSdJwtVc]) {
        self.client = client
        self.held = held
    }

    public func start(_ requestUri: String) async {
        do {
            let request = try await client.resolveRequest(requestUri)
            let m = client.match(request, held: held)
            resolved = request
            matches = m
            let queries = request.dcqlQuery.credentials.map { cq in
                QueryPresentation(queryId: cq.id, required: m.requiredQueryIds.contains(cq.id),
                                  candidates: m.candidatesByQuery[cq.id] ?? [])
            }
            state = .requestResolved(PresentationRequest(
                verifier: request.verifier, queries: queries,
                transactionData: request.transactionData, satisfiable: m.isSatisfiable()
            ))
        } catch let e as VpError {
            state = .failed(e)
        } catch {
            state = .failed(.responseFailed("\(error)"))
        }
    }

    public func respond(_ selection: PresentationSelection) async {
        guard let request = resolved, let m = matches else { return }
        state = .submitting
        do {
            let result = try await client.respond(request: request, matches: m, selection: selection, held: held)
            state = .completed(redirectUri: result.redirectUri)
        } catch let e as VpError {
            state = .failed(e)
        } catch {
            state = .failed(.responseFailed("\(error)"))
        }
    }

    public func decline() {
        state = .declined
    }
}
