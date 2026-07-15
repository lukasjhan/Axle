import AppleCore
import Foundation
import Wallet
import WalletAPI

/// Assembles the EUDI Wallet SDK on iOS — the iOS counterpart of android `DemoWallet.kt`.
///
/// Ports are the real Apple-platform adapters from `AppleCore`: keys live in the Secure Enclave, credentials
/// in the shared keychain group, and the activity log in the shared App Group container — so all three
/// survive relaunch and are reachable by the DC API provider extension. Logs are routed to the in-app
/// Debug screen (and OSLog) via `LogStoreLogger`.
enum DemoWallet {
    static let shared: Wallet = build()
    /// Held so a wallet reset can wipe persisted activity (`WalletModel.reset`).
    static let txStore = FileTransactionLogStore()

    private static func build() -> Wallet {
        Wallet.create(
            config: WalletConfig(
                issuance: IssuanceConfig(
                    clientId: "wallet-dev",
                    redirectUri: "eu.europa.ec.euidi://authorization"
                )
            ),
            ports: WalletPorts(
                secureAreas: [SecureEnclaveSecureArea()],
                storage: KeychainStorageDriver(),
                http: URLSessionTransport(),
                logger: LogStoreLogger(),
                transactionLogStore: txStore
            )
        )
    }
}
