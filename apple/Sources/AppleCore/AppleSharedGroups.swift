import Foundation

/// The App Group + keychain access group shared between the main app and the DC API provider extension.
///
/// The keychain access group is baked into every Secure Enclave key at creation (`kSecAttrAccessGroup` cannot be
/// changed afterwards, and SE private keys cannot be exported), so both processes MUST create/read keys under the
/// same value or the extension can never sign with the app's device keys. Both entitlements list this group.
public enum AppleSharedGroups {
    /// `com.apple.security.application-groups` — the shared container holding the credential store side-data and
    /// the transaction log (so a DC API presentation from the extension shows up in the app's Activity).
    public static let appGroup = "group.com.hopae.axle.wallet"

    /// `$(AppIdentifierPrefix)com.hopae.axle.wallet` resolved — the team-prefixed keychain group both the app and
    /// the `…​.idprovider` extension declare in `keychain-access-groups`, so they share device keys + stored blobs.
    public static let keychainAccessGroup = "P3A48743C4.com.hopae.axle.wallet"
}
