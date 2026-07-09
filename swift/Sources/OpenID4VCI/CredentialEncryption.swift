import CborCose
import Foundation
import SdJwt

/// How the wallet treats encrypted Credential Requests and Responses (OpenID4VCI §8.2, §10).
public enum CredentialEncryption: Sendable {
    /// Encrypt only when the issuer sets `encryption_required` (default; keeps plaintext otherwise).
    case whenRequired
    /// Encrypt whenever the issuer advertises `credential_response_encryption`.
    case preferred
    /// Always encrypt; fail when the issuer does not advertise support.
    case required
}

/// The ECDH-ES `alg` this SDK implements; §10 requires the JWE `alg` to equal the chosen JWK's `alg`.
private let ecdhEs = "ECDH-ES"

/// The content-encryption algorithms we can negotiate, most preferred first.
private let supportedEnc: [JweEnc] = [.a256gcm, .a128gcm, .a192gcm]

/// A negotiated encryption context for one Credential Request/Response pair (§10). Both directions are
/// used together: §8.2 requires the request to be encrypted whenever a `credential_response_encryption`
/// object is sent, so an attacker cannot substitute the wallet's response-encryption key.
public struct CredentialEncryptionSession {
    private let issuerKey: EcPublicKey
    private let issuerKid: String?
    private let requestEnc: JweEnc
    private let responseEnc: JweEnc
    private let recipient: JweRecipientKey

    /// The `credential_response_encryption` object to embed in the Credential Request.
    public func requestObject() -> JsonValue {
        .obj([("jwk", recipient.publicJwk(alg: ecdhEs)), ("enc", .str(responseEnc.rawValue))])
    }

    /// Encrypts the Credential Request JSON to the issuer's key; the body becomes a compact JWE.
    public func encryptRequest(_ json: String) throws -> String {
        try Jwe.encryptEcdhEs(plaintext: [UInt8](json.utf8), recipient: issuerKey, enc: requestEnc, kid: issuerKid)
    }

    public func decryptResponse(_ compact: String) throws -> JsonValue {
        let plaintext: [UInt8]
        do {
            plaintext = try recipient.decrypt(compact.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw VciError.protocolError("credential response JWE did not decrypt: \(error)")
        }
        guard let text = String(bytes: plaintext, encoding: .utf8),
              let json = try? JsonValue.parse(text), case .obj = json
        else { throw VciError.protocolError("encrypted credential response is not a JSON object") }
        return json
    }

    /// Resolves `policy` against the issuer's metadata, returning nil when the exchange stays plaintext.
    /// Throws when encryption is called for but the issuer cannot support the parts we need.
    static func negotiate(_ policy: CredentialEncryption, _ meta: CredentialIssuerMetadata) throws -> CredentialEncryptionSession? {
        let responseMeta = meta.credentialResponseEncryption
        let isRequired: Bool = {
            if case .required = policy { return true }
            return responseMeta?.encryptionRequired == true
        }()
        let wanted: Bool = {
            if isRequired { return true }
            if case .preferred = policy { return responseMeta != nil }
            return false
        }()
        if !wanted { return nil }

        guard let responseMeta else { throw VciError.metadata("issuer advertises no credential_response_encryption") }
        if !responseMeta.algValuesSupported.isEmpty && !responseMeta.algValuesSupported.contains(ecdhEs) {
            throw VciError.unsupported("issuer response encryption needs one of \(responseMeta.algValuesSupported); only \(ecdhEs) is implemented")
        }
        // §8.2: "Credential Request encryption MUST be used if the credential_response_encryption
        // parameter is included, to prevent it being substituted by an attacker."
        guard let requestMeta = meta.credentialRequestEncryption else {
            throw VciError.metadata("credential_response_encryption requires credential_request_encryption (§8.2)")
        }
        guard let jwk = requestMeta.jwks.first(where: { if case let .str(a)? = $0["alg"] { return a == ecdhEs }; return false }) else {
            throw VciError.unsupported("no \(ecdhEs) key in credential_request_encryption.jwks")
        }
        guard let issuerKey = JwkEc.fromJson(jwk) else {
            throw VciError.metadata("credential_request_encryption jwk is not an EC key")
        }
        var kid: String?
        if case let .str(k)? = jwk["kid"] { kid = k } // §10: the JWE header MUST repeat the chosen key's kid

        return CredentialEncryptionSession(
            issuerKey: issuerKey,
            issuerKid: kid,
            requestEnc: try pickEnc(requestMeta.encValuesSupported, "credential_request_encryption"),
            responseEnc: try pickEnc(responseMeta.encValuesSupported, "credential_response_encryption"),
            recipient: JweRecipientKey())
    }

    /// First mutually supported `enc`; an empty issuer list means "unconstrained".
    private static func pickEnc(_ issuerSupported: [String], _ where_: String) throws -> JweEnc {
        if issuerSupported.isEmpty { return .a128gcm }
        guard let picked = supportedEnc.first(where: { issuerSupported.contains($0.rawValue) }) else {
            throw VciError.unsupported("\(where_) offers \(issuerSupported); this SDK implements \(supportedEnc.map(\.rawValue))")
        }
        return picked
    }
}
