import Foundation
import Security
import WalletAPI

/// `StorageDriver` backed by the **keychain** — the iOS counterpart of android/core `FileStorageDriver`,
/// but encrypted at rest by the OS. Each `(collection, key)` is a generic-password item whose service is
/// `"<service>.<collection>"` and account is `key`. Items live in the shared access group so the DC API
/// provider extension reads what the app wrote.
///
/// Accessibility is `AfterFirstUnlockThisDeviceOnly`: the extension may be woken while the device is
/// locked (after the first post-boot unlock), and credentials must never sync off-device.
public final class KeychainStorageDriver: StorageDriver, @unchecked Sendable {
    private let service: String
    private let accessGroup: String?

    public init(service: String = "com.hopae.axle.wallet.storage", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func put(collection: String, key: String, value: [UInt8]) async throws {
        let match = query(collection: collection, key: key)
        let update: [CFString: Any] = [kSecValueData: Data(value)]
        let status = SecItemUpdate(match as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = match
            add[kSecValueData] = Data(value)
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StorageError.keychain(addStatus) }
        default:
            throw StorageError.keychain(status)
        }
    }

    public func get(collection: String, key: String) async throws -> [UInt8]? {
        var q = query(collection: collection, key: key)
        q[kSecReturnData] = true
        q[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw StorageError.keychain(status) }
            return [UInt8](data)
        case errSecItemNotFound:
            return nil
        default:
            throw StorageError.keychain(status)
        }
    }

    public func delete(collection: String, key: String) async throws {
        let status = SecItemDelete(query(collection: collection, key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError.keychain(status)
        }
    }

    public func keys(collection: String) async throws -> [String] {
        var q = query(collection: collection)
        q[kSecReturnAttributes] = true
        q[kSecMatchLimit] = kSecMatchLimitAll
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            let rows = item as? [[String: Any]] ?? []
            return rows.compactMap { $0[kSecAttrAccount as String] as? String }
        case errSecItemNotFound:
            return []
        default:
            throw StorageError.keychain(status)
        }
    }

    /// The keychain has no transactions, so this runs the block against the live store with no rollback —
    /// the same best-effort semantics as android/core `FileStorageDriver.transaction`.
    public func transaction(_ block: @Sendable (any StorageTx) async throws -> Void) async throws {
        try await block(Tx(driver: self))
    }

    private func query(collection: String, key: String? = nil) -> [CFString: Any] {
        var q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "\(service).\(collection)",
        ]
        if let key { q[kSecAttrAccount] = key }
        if let accessGroup { q[kSecAttrAccessGroup] = accessGroup }
        return q
    }

    private struct Tx: StorageTx {
        let driver: KeychainStorageDriver
        func put(collection: String, key: String, value: [UInt8]) async throws {
            try await driver.put(collection: collection, key: key, value: value)
        }
        func get(collection: String, key: String) async throws -> [UInt8]? {
            try await driver.get(collection: collection, key: key)
        }
        func delete(collection: String, key: String) async throws {
            try await driver.delete(collection: collection, key: key)
        }
    }
}

public enum StorageError: Error, CustomStringConvertible {
    case keychain(OSStatus)

    public var description: String {
        switch self {
        case let .keychain(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            return "keychain error \(status): \(message)"
        }
    }
}
