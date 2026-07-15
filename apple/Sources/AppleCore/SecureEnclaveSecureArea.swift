import CborCose
import CryptoKit
import Foundation
import Security
import WalletAPI

/// `SecureArea` backed by the **Secure Enclave** — the iOS counterpart of android/core
/// `AndroidKeystoreSecureArea`. Private keys are generated inside the SE, never leave it, and persist
/// across launches (a keychain reference holds the encrypted blob). One SE key serves both ECDSA
/// signing and ECDH key agreement, matching the Android dual-purpose (SIGN | AGREE_KEY) key.
///
/// Secure Enclave is **P-256 only**, so `capabilities.algorithms = [.es256]`; es384/es512 are
/// impossible (no impact — mdoc device keys and SD-JWT holder keys are ES256).
///
/// `attestation` returns `nil`: Apple key attestation is App Attest (`DCAppAttestService`), a separate
/// mechanism wired later; the SDK's HAIP key attestation routes through the wallet-provider backend.
public final class SecureEnclaveSecureArea: SecureArea, @unchecked Sendable {
    public let id: SecureAreaId

    /// Keychain access group the keys live in. `nil` uses the app's default group — the first entry of
    /// the `keychain-access-groups` entitlement (`P3A48743C4.com.hopae.axle.wallet`), which is the group
    /// shared with the DC API provider extension. `kSecAttrAccessGroup` is fixed at key creation and SE
    /// keys cannot be exported, so this must be the shared group from the very first key.
    private let accessGroup: String?

    public init(id: SecureAreaId = SecureAreaId("secure-enclave"), accessGroup: String? = nil) {
        self.id = id
        self.accessGroup = accessGroup
    }

    public var capabilities: SecureAreaCapabilities {
        SecureAreaCapabilities(
            algorithms: [.es256],
            hardwareBacked: true,
            userAuthentication: false,
            keyAttestation: false,
            keyAgreement: true
        )
    }

    public func createKey(spec: KeySpec) async throws -> KeyInfo {
        guard spec.algorithm == .es256 else {
            throw SecureEnclaveError.unsupportedAlgorithm(spec.algorithm)
        }
        let alias = "eudi-\(UUID().uuidString)"

        var acError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            &acError
        ) else {
            throw SecureEnclaveError.accessControl(acError?.takeRetainedValue())
        }

        var privateKeyAttrs: [CFString: Any] = [
            kSecAttrIsPermanent: true,
            kSecAttrApplicationTag: Data(alias.utf8),
            kSecAttrAccessControl: access,
        ]
        if let accessGroup { privateKeyAttrs[kSecAttrAccessGroup] = accessGroup }

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrTokenID: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs: privateKeyAttrs,
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw SecureEnclaveError.keyCreation(error?.takeRetainedValue())
        }
        let publicKey = try Self.ecPublicKey(from: privateKey)
        return KeyInfo(handle: KeyHandle(secureArea: id, alias: alias), algorithm: .es256, publicKey: publicKey)
    }

    public func publicKey(key: KeyHandle) async throws -> EcPublicKey {
        try Self.ecPublicKey(from: try loadPrivateKey(alias: key.alias))
    }

    public func sign(key: KeyHandle, algorithm: SigningAlgorithm, data: [UInt8], hint: AuthorizationHint?) async throws -> [UInt8] {
        guard algorithm == .es256 else { throw SecureEnclaveError.unsupportedAlgorithm(algorithm) }
        let privateKey = try loadPrivateKey(alias: key.alias)
        var error: Unmanaged<CFError>?
        guard let der = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, Data(data) as CFData, &error) as Data? else {
            throw SecureEnclaveError.signing(error?.takeRetainedValue())
        }
        // SecKey emits DER; the port contract wants raw r||s. CryptoKit does the conversion.
        let raw = try P256.Signing.ECDSASignature(derRepresentation: der).rawRepresentation
        return [UInt8](raw)
    }

    public func keyAgreement(key: KeyHandle, peerPublicKey: EcPublicKey, hint: AuthorizationHint?) async throws -> [UInt8] {
        let privateKey = try loadPrivateKey(alias: key.alias)
        let peer = try Self.secKey(from: peerPublicKey)
        var error: Unmanaged<CFError>?
        guard let shared = SecKeyCopyKeyExchangeResult(
            privateKey, .ecdhKeyExchangeStandard, peer, [CFString: Any]() as CFDictionary, &error
        ) as Data? else {
            throw SecureEnclaveError.keyAgreement(error?.takeRetainedValue())
        }
        return [UInt8](shared)
    }

    public func attestation(key: KeyHandle, challenge: [UInt8]) async throws -> KeyAttestation? {
        nil
    }

    public func deleteKey(key: KeyHandle) async throws {
        var query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: Data(key.alias.utf8),
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureEnclaveError.deletion(status)
        }
    }

    // MARK: - Keychain lookup

    private func loadPrivateKey(alias: String) throws -> SecKey {
        var query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: Data(alias.utf8),
            kSecReturnRef: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let item else {
            throw SecureEnclaveError.keyNotFound(alias: alias, status: status)
        }
        // Safe: the query pins kSecClassKey, so a success returns a SecKey.
        return item as! SecKey
    }

    // MARK: - EC key conversions

    private static func ecPublicKey(from privateKey: SecKey) throws -> EcPublicKey {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecureEnclaveError.publicKeyExtraction
        }
        var error: Unmanaged<CFError>?
        guard let external = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw SecureEnclaveError.publicKeyExtraction
        }
        // X9.63 uncompressed for P-256: 0x04 || X(32) || Y(32) = 65 bytes.
        let bytes = [UInt8](external)
        guard bytes.count == 65, bytes[0] == 0x04 else {
            throw SecureEnclaveError.malformedPublicKey
        }
        return EcPublicKey(curve: .p256, x: Array(bytes[1..<33]), y: Array(bytes[33..<65]))
    }

    private static func secKey(from publicKey: EcPublicKey) throws -> SecKey {
        var x963: [UInt8] = [0x04]
        x963 += leftPad(publicKey.x, 32)
        x963 += leftPad(publicKey.y, 32)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(Data(x963) as CFData, attributes as CFDictionary, &error) else {
            throw SecureEnclaveError.malformedPublicKey
        }
        return key
    }

    private static func leftPad(_ bytes: [UInt8], _ size: Int) -> [UInt8] {
        bytes.count >= size ? bytes : [UInt8](repeating: 0, count: size - bytes.count) + bytes
    }
}

public enum SecureEnclaveError: Error, CustomStringConvertible {
    case unsupportedAlgorithm(SigningAlgorithm)
    case accessControl(CFError?)
    case keyCreation(CFError?)
    case keyNotFound(alias: String, status: OSStatus)
    case signing(CFError?)
    case keyAgreement(CFError?)
    case deletion(OSStatus)
    case publicKeyExtraction
    case malformedPublicKey

    public var description: String {
        switch self {
        case let .unsupportedAlgorithm(algorithm):
            return "Secure Enclave supports ES256 only, not \(algorithm)"
        case let .accessControl(error):
            return "access control creation failed: \(String(describing: error))"
        case let .keyCreation(error):
            return "Secure Enclave key creation failed: \(String(describing: error))"
        case let .keyNotFound(alias, status):
            return "key '\(alias)' not found (OSStatus \(status))"
        case let .signing(error):
            return "signing failed: \(String(describing: error))"
        case let .keyAgreement(error):
            return "ECDH failed: \(String(describing: error))"
        case let .deletion(status):
            return "key deletion failed (OSStatus \(status))"
        case .publicKeyExtraction:
            return "could not extract the public key"
        case .malformedPublicKey:
            return "malformed EC public key"
        }
    }
}
