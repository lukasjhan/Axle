import AppleCore
import Foundation
import Wallet

/// The wallet the extension process uses to answer a DC API request. It shares the app's Secure Enclave keys and
/// keychain-stored credentials through the shared keychain access group, so it can read the selected credential
/// and sign a DeviceResponse with that credential's device key. Offline by design — no issuance, no trusted-list
/// fetch, no wallet-provider: the extension only reads and signs.
///
/// The transaction log points at the shared App Group container, so a DC API presentation made here shows up in
/// the app's Activity tab.
enum ExtensionWallet {
    static let shared: Wallet = build()

    private static func build() -> Wallet {
        let secureArea = SecureEnclaveSecureArea(accessGroup: AppleSharedGroups.keychainAccessGroup)
        let storage = KeychainStorageDriver(accessGroup: AppleSharedGroups.keychainAccessGroup)
        return Wallet.create(
            config: WalletConfig(
                issuance: IssuanceConfig(clientId: "wallet-dev", redirectUri: "eu.europa.ec.euidi://authorization"),
                trust: TrustConfig(issuerAnchorsDer: [], readerAnchorsDer: [], registrarAnchorsDer: []),
                transactionLog: TransactionLogConfig(recordFailures: false)),
            ports: WalletPorts(
                secureAreas: [secureArea],
                storage: storage,
                http: URLSessionTransport(),
                transactionLogStore: FileTransactionLogStore()))
    }
}
