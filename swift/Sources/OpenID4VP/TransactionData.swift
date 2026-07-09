import SdJwt

/// One parsed OpenID4VP `transaction_data` object (§8.4 / §5.1). `raw` is the original base64url string —
/// the hash bound into the KB-JWT (`transaction_data_hashes`, B.3.3.1) is computed over it verbatim, without
/// base64url-decoding first.
public struct TransactionData {
    public let raw: String
    public let type: String
    /// DCQL credential-query ids that can authorize this transaction; the wallet binds it to exactly one (§5.1).
    public let credentialIds: [String]
    /// Allowed hash algorithms (`transaction_data_hashes_alg`); nil → the default `sha-256` (B.3.3.1).
    public let hashAlgorithms: [String]?

    /// Parses a base64url-encoded transaction_data string; throws `VpError.invalidTransactionData` if malformed.
    public static func parse(_ raw: String) throws -> TransactionData {
        guard let decoded = try? Base64Url.decodeToString(raw), let json = try? JsonValue.parse(decoded),
              case .obj = json else {
            throw VpError.invalidTransactionData("entry is not a base64url-encoded JSON object")
        }
        guard case let .str(type)? = json["type"] else {
            throw VpError.invalidTransactionData("entry is missing a string 'type'")
        }
        guard case let .arr(idValues)? = json["credential_ids"] else {
            throw VpError.invalidTransactionData("entry is missing a non-empty 'credential_ids'")
        }
        let ids = idValues.compactMap { v -> String? in if case let .str(s) = v { return s }; return nil }
        if ids.isEmpty { throw VpError.invalidTransactionData("entry is missing a non-empty 'credential_ids'") }
        var algs: [String]?
        if case let .arr(algValues)? = json["transaction_data_hashes_alg"] {
            let a = algValues.compactMap { v -> String? in if case let .str(s) = v { return s }; return nil }
            algs = a.isEmpty ? nil : a
        }
        return TransactionData(raw: raw, type: type, credentialIds: ids, hashAlgorithms: algs)
    }
}
