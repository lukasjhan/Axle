import AppleCore
import Foundation
import Wallet
import WalletAPI

/// Assembles the EUDI Wallet SDK on iOS — the iOS counterpart of android `DemoWallet.kt`.
///
/// Ports are the real Apple-platform adapters from `AppleCore`: keys live in the Secure Enclave and
/// credentials in the shared keychain group, so both survive relaunch and are reachable by the DC API
/// provider extension. The transaction log is still the in-memory default (a persistent App Group store
/// lands with the Activity screen).
enum DemoWallet {
    static let shared: Wallet = build()

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
                logger: OSLogWalletLogger()
            )
        )
    }
}
