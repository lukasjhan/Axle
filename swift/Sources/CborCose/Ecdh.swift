import Crypto
import Foundation

/// Curve-generic ephemeral ECDH (P-256 / P-384 / P-521) for mdoc session keys (ISO 18013-5 §9.1.5.2) and
/// JWE ECDH-ES. CryptoKit's key-agreement types are per-curve, so this wraps them behind one API keyed by
/// `EcCurve`; the private scalar never leaves the value.
public enum Ecdh {
    public struct PrivateKey {
        private enum Backing {
            case p256(P256.KeyAgreement.PrivateKey)
            case p384(P384.KeyAgreement.PrivateKey)
            case p521(P521.KeyAgreement.PrivateKey)
        }
        private let backing: Backing
        public let publicKey: EcPublicKey
        public var curve: EcCurve { publicKey.curve }

        private init(_ backing: Backing) {
            self.backing = backing
            switch backing {
            case let .p256(k): publicKey = Self.publicKey(.p256, k.publicKey.x963Representation)
            case let .p384(k): publicKey = Self.publicKey(.p384, k.publicKey.x963Representation)
            case let .p521(k): publicKey = Self.publicKey(.p521, k.publicKey.x963Representation)
            }
        }

        /// A fresh ephemeral key on `curve`.
        public static func generate(_ curve: EcCurve) -> PrivateKey {
            switch curve {
            case .p256: return PrivateKey(.p256(P256.KeyAgreement.PrivateKey()))
            case .p384: return PrivateKey(.p384(P384.KeyAgreement.PrivateKey()))
            case .p521: return PrivateKey(.p521(P521.KeyAgreement.PrivateKey()))
            }
        }

        /// Rebuilds a key from its raw big-endian scalar `d` on `curve`.
        public init(curve: EcCurve, rawD: [UInt8]) throws {
            switch curve {
            case .p256: self.init(.p256(try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(rawD))))
            case .p384: self.init(.p384(try P384.KeyAgreement.PrivateKey(rawRepresentation: Data(rawD))))
            case .p521: self.init(.p521(try P521.KeyAgreement.PrivateKey(rawRepresentation: Data(rawD))))
            }
        }

        /// Raw ECDH shared secret (Zab) with `peer` (on the same curve).
        public func sharedSecret(with peer: EcPublicKey) throws -> [UInt8] {
            let x963 = Data([0x04] + pad(peer.x, peer.curve.coordinateSize) + pad(peer.y, peer.curve.coordinateSize))
            switch backing {
            case let .p256(k):
                return try k.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: x963)).withUnsafeBytes { [UInt8]($0) }
            case let .p384(k):
                return try k.sharedSecretFromKeyAgreement(with: P384.KeyAgreement.PublicKey(x963Representation: x963)).withUnsafeBytes { [UInt8]($0) }
            case let .p521(k):
                return try k.sharedSecretFromKeyAgreement(with: P521.KeyAgreement.PublicKey(x963Representation: x963)).withUnsafeBytes { [UInt8]($0) }
            }
        }

        private static func publicKey(_ curve: EcCurve, _ x963: Data) -> EcPublicKey {
            let xy = [UInt8](x963.dropFirst()) // strip the 0x04 uncompressed-point prefix
            let size = curve.coordinateSize
            return EcPublicKey(curve: curve, x: Array(xy.prefix(size)), y: Array(xy.suffix(size)))
        }
    }
}

private func pad(_ b: [UInt8], _ size: Int) -> [UInt8] {
    b.count >= size ? Array(b.suffix(size)) : [UInt8](repeating: 0, count: size - b.count) + b
}
