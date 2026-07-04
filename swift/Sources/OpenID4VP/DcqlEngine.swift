import Foundation
import SdJwt

/// A credential the wallet holds, in a shape DCQL can match against.
public protocol QueryableCredential {
    var credentialId: String { get }
    var format: String { get }
    var vct: String? { get }
    var docType: String? { get }
    /// Processed claim tree (SD-JWT VC: disclosed + always-visible claims).
    var claims: JsonValue { get }
}

/// One held credential that satisfies a credential query, plus the concrete paths to disclose.
public struct CandidateMatch {
    public let query: CredentialQuery
    public let credential: QueryableCredential
    public let disclosedPaths: [[String]]
}

public struct DcqlMatchResult {
    public let candidatesByQuery: [String: [CandidateMatch]]
    public let credentialSets: [CredentialSetQuery]?

    /// Query ids the response must answer (from credential_sets, or all when absent).
    public var requiredQueryIds: Set<String> {
        guard let sets = credentialSets else { return Set(candidatesByQuery.keys) }
        let required = Set(sets.filter { $0.required }.flatMap { $0.options.flatMap { $0 } })
        return required.isEmpty ? Set(candidatesByQuery.keys) : required
    }

    public func isSatisfiable() -> Bool {
        let answerable = Set(candidatesByQuery.filter { !$0.value.isEmpty }.keys)
        guard let sets = credentialSets else { return Set(candidatesByQuery.keys).isSubset(of: answerable) }
        return sets.filter { $0.required }.allSatisfy { set in
            set.options.contains { option in option.allSatisfy { answerable.contains($0) } }
        }
    }
}

/// DCQL matching engine (OpenID4VP §6). Pure logic — no I/O.
public enum DcqlEngine {

    public static func match(_ query: DcqlQuery, held: [QueryableCredential]) -> DcqlMatchResult {
        var byQuery: [String: [CandidateMatch]] = [:]
        for cq in query.credentials {
            byQuery[cq.id] = held.compactMap { matchCredential(cq, $0) }
        }
        return DcqlMatchResult(candidatesByQuery: byQuery, credentialSets: query.credentialSets)
    }

    public static func matchCredential(_ cq: CredentialQuery, _ credential: QueryableCredential) -> CandidateMatch? {
        if credential.format != cq.format { return nil }
        if let meta = cq.meta {
            if let vctValues = meta.vctValues {
                guard let vct = credential.vct, vctValues.contains(vct) else { return nil }
            }
            if let doctype = meta.doctypeValue, credential.docType != doctype { return nil }
        }

        let claimsToUse: [ClaimQuery]
        if cq.claims.isEmpty {
            claimsToUse = []
        } else if let claimSets = cq.claimSets {
            var byId: [String: ClaimQuery] = [:]
            for c in cq.claims where c.id != nil { byId[c.id!] = c }
            guard let chosen = claimSets.first(where: { set in
                set.allSatisfy { id in byId[id].map { satisfies(credential, $0).0 } ?? false }
            }) else { return nil }
            claimsToUse = chosen.compactMap { byId[$0] }
        } else {
            claimsToUse = cq.claims
        }

        var disclosed: [[String]] = []
        for claim in claimsToUse {
            let (ok, paths) = satisfies(credential, claim)
            if !ok { return nil }
            disclosed.append(contentsOf: paths)
        }
        // distinct, preserving order
        var seen = Set<[String]>()
        let unique = disclosed.filter { seen.insert($0).inserted }
        return CandidateMatch(query: cq, credential: credential, disclosedPaths: unique)
    }

    private static func satisfies(_ credential: QueryableCredential, _ claim: ClaimQuery) -> (Bool, [[String]]) {
        let resolved = resolvePath(credential.claims, claim.path, [])
        if resolved.isEmpty { return (false, []) }
        guard let values = claim.values else { return (true, resolved.map { $0.0 }) }
        let matching = resolved.filter { (_, v) in values.contains { $0 == v } }
        return matching.isEmpty ? (false, []) : (true, matching.map { $0.0 })
    }

    public static func resolvePath(_ node: JsonValue, _ path: [PathElement], _ prefix: [String]) -> [([String], JsonValue)] {
        guard let head = path.first else { return [(prefix, node)] }
        let tail = Array(path.dropFirst())
        switch head {
        case let .key(name):
            guard let v = node[name] else { return [] }
            return resolvePath(v, tail, prefix + [name])
        case let .index(i):
            guard case let .arr(items) = node, i >= 0, i < items.count else { return [] }
            return resolvePath(items[i], tail, prefix + [String(i)])
        case .wildcard:
            guard case let .arr(items) = node else { return [] }
            return items.enumerated().flatMap { resolvePath($0.element, tail, prefix + [String($0.offset)]) }
        }
    }
}
