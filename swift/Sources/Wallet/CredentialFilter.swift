import WalletAPI

/// Local (non-network) predicate over stored credentials. For DCQL semantics use `credentials.match`.
public enum CredentialFilter {
    case all
    case byVct(String)
    case byDocType(String)

    func matches(_ credential: Credential) -> Bool {
        switch self {
        case .all:
            return true
        case let .byVct(vct):
            if case let .sdJwtVc(v) = credential.format { return v == vct }
            return false
        case let .byDocType(docType):
            if case let .msoMdoc(d) = credential.format { return d == docType }
            return false
        }
    }
}
