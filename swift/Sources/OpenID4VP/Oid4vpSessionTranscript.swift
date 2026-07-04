import CborCose
import Crypto
import Foundation
import SdJwt

/// The mdoc `SessionTranscript` for OpenID4VP (OpenID4VP 1.0, "Handover and SessionTranscript
/// Definitions"): `[null, null, OpenID4VPHandover]` where
/// `OpenID4VPHandover = ["OpenID4VPHandover", SHA-256(CBOR([client_id, nonce, jwk_thumbprint, response_uri]))]`.
/// `jwk_thumbprint` is the verifier encryption key's RFC 7638 thumbprint, or null when unencrypted.
public enum Oid4vpSessionTranscript {

    public static func build(clientId: String, responseUri: String?, nonce: String, verifierJwkThumbprint: [UInt8]?) throws -> Cbor {
        let handoverInfo = Cbor.array([
            .text(clientId),
            .text(nonce),
            verifierJwkThumbprint.map { Cbor.bytes($0) } ?? .null,
            .text(responseUri ?? ""),
        ])
        let hash = [UInt8](SHA256.hash(data: Data(try CborEncoder.encode(handoverInfo))))
        let handover = Cbor.array([.text("OpenID4VPHandover"), .bytes(hash)])
        return .array([.null, .null, handover])
    }
}

/// RFC 7638 JWK thumbprint (SHA-256) of an EC public key — members in lexicographic order.
public func ecJwkThumbprint(_ key: EcPublicKey) -> [UInt8] {
    let crv: String
    switch key.curve {
    case .p256: crv = "P-256"
    case .p384: crv = "P-384"
    case .p521: crv = "P-521"
    }
    let json = #"{"crv":"\#(crv)","kty":"EC","x":"\#(Base64Url.encode(key.x))","y":"\#(Base64Url.encode(key.y))"}"#
    return [UInt8](SHA256.hash(data: Data(json.utf8)))
}
