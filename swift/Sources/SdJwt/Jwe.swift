import CborCose
import Crypto
import Foundation

public struct JweError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

/// JWE content-encryption algorithms this SDK supports (AES-GCM, RFC 7518 §5.3).
public enum JweEnc: String, Sendable {
    case a128gcm = "A128GCM"
    case a192gcm = "A192GCM"
    case a256gcm = "A256GCM"

    var keyBytes: Int {
        switch self {
        case .a128gcm: return 16
        case .a192gcm: return 24
        case .a256gcm: return 32
        }
    }

    public static func from(_ id: String) -> JweEnc? { JweEnc(rawValue: id) }
}

/// JWE with ECDH-ES direct key agreement (RFC 7518 §4.6) + AES-GCM. P-256 only.
/// An ephemeral EC key pair the wallet publishes as a JWE recipient — OpenID4VCI §8.2's
/// `credential_response_encryption.jwk`. Short-lived transport material, not credential key material, so
/// it is generated in process rather than in a `SecureArea`; the private scalar never leaves this object.
public struct JweRecipientKey {
    private let privateKey: Ecdh.PrivateKey
    public var publicKey: EcPublicKey { privateKey.publicKey }

    public init(curve: EcCurve = .p256) { privateKey = Ecdh.PrivateKey.generate(curve) }
    public static func generate(_ curve: EcCurve = .p256) -> JweRecipientKey { JweRecipientKey(curve: curve) }

    /// The public JWK to hand the issuer. §10 requires `alg` to be present on the chosen key.
    public func publicJwk(alg: String = "ECDH-ES") -> JsonValue {
        guard case let .obj(entries) = JwkEc.toJson(publicKey) else { return JwkEc.toJson(publicKey) }
        return .obj(entries + [("use", .str("enc")), ("alg", .str(alg))])
    }

    public func decrypt(_ compact: String) throws -> [UInt8] {
        try Jwe.decryptEcdhEs(compact, recipient: privateKey)
    }
}

/// This is the OpenID4VP `direct_post.jwt` response-encryption path.
public enum Jwe {

    /// Encrypts `plaintext` to `recipient` (ECDH-ES direct). Returns compact JWE.
    ///
    /// `kid` identifies the recipient key: OpenID4VCI §10 requires the JWE header to echo the `kid` of the
    /// JWK it encrypted to, when that JWK has one.
    public static func encryptEcdhEs(
        plaintext: [UInt8],
        recipient: EcPublicKey,
        enc: JweEnc = .a128gcm,
        apu: [UInt8]? = nil,
        apv: [UInt8]? = nil,
        kid: String? = nil
    ) throws -> String {
        // ECDH-ES on the recipient's curve (P-256 / P-384 / P-521). ConcatKDF (RFC 7518 §4.6.2) is SHA-256
        // regardless of curve, so nothing else depends on the curve.
        let ephemeral = Ecdh.PrivateKey.generate(recipient.curve)
        let z = try ephemeral.sharedSecret(with: recipient)
        let cek = concatKdf(z: z, keyBytes: enc.keyBytes, algId: enc.rawValue, apu: apu ?? [], apv: apv ?? [])

        let epk = JwkEc.toJson(ephemeral.publicKey)
        var headerEntries: [(String, JsonValue)] = [
            ("alg", .str("ECDH-ES")),
            ("enc", .str(enc.rawValue)),
            ("epk", epk),
        ]
        if let kid { headerEntries.append(("kid", .str(kid))) }
        if let apu { headerEntries.append(("apu", .str(Base64Url.encode(apu)))) }
        if let apv { headerEntries.append(("apv", .str(Base64Url.encode(apv)))) }
        let headerB64 = Base64Url.encode(JsonValue.obj(headerEntries).serialize())
        let aad = [UInt8](headerB64.utf8)

        let iv = (0..<12).map { _ in UInt8.random(in: .min ... .max) }
        let sealed = try AES.GCM.seal(
            Data(plaintext), using: SymmetricKey(data: cek),
            nonce: try AES.GCM.Nonce(data: Data(iv)), authenticating: Data(aad)
        )
        return [
            headerB64, "",
            Base64Url.encode(iv),
            Base64Url.encode([UInt8](sealed.ciphertext)),
            Base64Url.encode([UInt8](sealed.tag)),
        ].joined(separator: ".")
    }

    /// Decrypts a compact ECDH-ES JWE with the recipient private key (its curve must match the header `epk`).
    public static func decryptEcdhEs(_ compact: String, recipient: Ecdh.PrivateKey) throws -> [UInt8] {
        let parts = compact.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 else { throw JweError("compact JWE must have 5 parts") }
        guard case let .obj(hdr)? = try? JsonValue.parse(try Base64Url.decodeToString(parts[0])) else {
            throw JweError("bad header")
        }
        let header = JsonValue.obj(hdr)
        guard case .str("ECDH-ES")? = header["alg"] else { throw JweError("unsupported alg") }
        guard case let .str(encId)? = header["enc"], let enc = JweEnc.from(encId) else { throw JweError("unsupported enc") }
        guard let epkJson = header["epk"], let epk = JwkEc.fromJson(epkJson), epk.curve == recipient.curve else {
            throw JweError("bad epk")
        }
        var apu: [UInt8] = []
        if case let .str(s)? = header["apu"] { apu = try Base64Url.decode(s) }
        var apv: [UInt8] = []
        if case let .str(s)? = header["apv"] { apv = try Base64Url.decode(s) }

        let z = try recipient.sharedSecret(with: epk)
        let cek = concatKdf(z: z, keyBytes: enc.keyBytes, algId: enc.rawValue, apu: apu, apv: apv)

        let iv = try Base64Url.decode(parts[2])
        let ct = try Base64Url.decode(parts[3])
        let tag = try Base64Url.decode(parts[4])
        let box = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: Data(iv)), ciphertext: Data(ct), tag: Data(tag))
        let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: cek), authenticating: Data(parts[0].utf8))
        return [UInt8](plaintext)
    }

    /// Concat KDF (NIST SP 800-56A) for ECDH-ES direct (RFC 7518 §4.6.2).
    static func concatKdf(z: [UInt8], keyBytes: Int, algId: String, apu: [UInt8], apv: [UInt8]) -> [UInt8] {
        let hashLen = 32
        let reps = (keyBytes + hashLen - 1) / hashLen
        var otherInfo = lengthPrefixed([UInt8](algId.utf8))
        otherInfo += lengthPrefixed(apu)
        otherInfo += lengthPrefixed(apv)
        otherInfo += uint32(keyBytes * 8)

        var out: [UInt8] = []
        for i in 1...reps {
            var hasher = SHA256()
            hasher.update(data: Data(uint32(i)))
            hasher.update(data: Data(z))
            hasher.update(data: Data(otherInfo))
            out += Array(hasher.finalize())
        }
        return Array(out.prefix(keyBytes))
    }

    private static func lengthPrefixed(_ data: [UInt8]) -> [UInt8] { uint32(data.count) + data }

    private static func uint32(_ v: Int) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }
}
