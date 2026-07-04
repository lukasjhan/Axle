import Crypto
import Foundation
import SdJwt

/// An SD-JWT VC the wallet holds, usable as a DCQL match target and presentable over OpenID4VP.
public struct HeldSdJwtVc: QueryableCredential {
    public let credentialId: String
    let sdJwt: SdJwt
    let holderSigner: any JwsSigner

    public let format = "dc+sd-jwt"
    public let claims: JsonValue
    public let docType: String? = nil

    public var vct: String? {
        if case let .str(v)? = claims["vct"] { return v }
        return nil
    }

    public init(credentialId: String, sdJwt: SdJwt, holderSigner: any JwsSigner) throws {
        self.credentialId = credentialId
        self.sdJwt = sdJwt
        self.holderSigner = holderSigner
        self.claims = try SdJwtHolder.processedClaims(sdJwt)
    }

    /// Selects the `disclosedPaths` disclosures and appends a KB-JWT bound to `audience` + `nonce`.
    public func present(
        disclosedPaths: [[String]],
        audience: String,
        nonce: String,
        issuedAt: Int64,
        transactionData: [String]? = nil
    ) async throws -> String {
        let pathSet = Set(disclosedPaths)
        var extra: [(String, JsonValue)] = []
        if let td = transactionData, !td.isEmpty {
            extra.append(("transaction_data_hashes", .arr(td.map { .str(sha256B64($0)) })))
            extra.append(("transaction_data_hashes_alg", .str("sha-256")))
        }
        let presented = try await SdJwtHolder.presentWithKeyBinding(
            sdJwt, select: { pathSet.contains($0) },
            audience: audience, nonce: nonce, issuedAt: issuedAt, signer: holderSigner, extraClaims: extra
        )
        return presented.serialize()
    }

    private func sha256B64(_ s: String) -> String {
        Base64Url.encode([UInt8](SHA256.hash(data: Data(s.utf8))))
    }
}
