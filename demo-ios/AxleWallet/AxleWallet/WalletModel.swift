import AppleCore // TransactionLogEntry (re-exported)
import AppleDcApi // DcApiRegistrar — registers mdocs with the OS Digital Credentials registry
import Foundation
import Observation
import Wallet
import WalletAPI // CredentialId

/// App-level coordinator and single source of truth for the tab UI — the iOS counterpart of android
/// `WalletRoot`. Holds the loaded credentials + activity (so every tab and both detail screens read one
/// consistent snapshot), routes scanned/opened URIs by scheme through `handleURI` (exactly like android
/// `handleUri`), and drives the issuance/presentation flow overlays.
@MainActor
@Observable
final class WalletModel {
    // Loaded data (single snapshot shared by Home/Documents/Activity and the detail screens).
    var credentials: [Credential] = []
    var transactions: [TransactionLogEntry] = []

    /// Selected bottom tab; Home's "See all" links switch tabs through this (android `navigateTab`).
    var selectedTab: WalletTab = .home

    // Flow / overlay state.
    var busy: String?
    var issuingOffer: CredentialOffer?
    var presentingSession: PresentationSession?
    /// Drives the QR scanner sheet (hosted at the `WalletHome` root; any tab can raise it).
    var showScanner = false

    let wallet = DemoWallet.shared

    static let offerSchemes: Set<String> = ["openid-credential-offer", "haip-vci"]
    static let vpSchemes: Set<String> = ["openid4vp", "eudi-openid4vp", "mdoc-openid4vp", "haip-vp"]

    /// Initial load plus a long-lived subscription to credential changes, so lists stay live after
    /// issuance/deletion without manual refresh tokens (android `credentials.changes.collect`).
    func start() async {
        await refresh()
        await syncDcApi()
        for await _ in await wallet.credentials.changes() {
            await refresh()
            await syncDcApi()
        }
    }

    /// Register the wallet's mdoc credentials with the OS Digital Credentials registry (iOS 26+) so Safari can
    /// offer Axle Wallet for an `org-iso-mdoc` request — on first load and on every credential change (android
    /// `MainActivity` re-registers the same way). No-op if the OS lacks the registry or the entitlement.
    private func syncDcApi() async {
        if #available(iOS 26.0, *) {
            await DcApiRegistrar.sync(wallet: wallet) { LogStore.shared.log($0) }
        }
    }

    func refresh() async {
        if let creds = try? await wallet.credentials.list() { credentials = creds }
        transactions = await wallet.transactions.history()
    }

    /// Unified inbound router (holder side): dispatch by the scanned/opened URI's scheme (android `handleUri`).
    func handleURI(_ uri: String, source: String) {
        let scheme = uri.components(separatedBy: "://").first?.lowercased() ?? ""
        LogStore.shared.log("\(source) [\(scheme)]: \(uri.prefix(140))\(uri.count > 140 ? "…" : "")")
        if Self.offerSchemes.contains(scheme) {
            Task { await resolveOffer(uri) }
        } else if Self.vpSchemes.contains(scheme) {
            // The session resolves the request internally; PresentView shows a "Resolving request…"
            // state until `.requestResolved`, then the consent screen.
            presentingSession = wallet.presentation.start(uri)
        } else {
            LogStore.shared.log("⚠️ Unrecognized scheme '\(scheme)' (expected an offer or presentation link)")
        }
    }

    private func resolveOffer(_ uri: String) async {
        busy = "Resolving offer…"
        defer { busy = nil }
        do {
            issuingOffer = try await wallet.issuance.resolveOffer(uri)
        } catch {
            LogStore.shared.log("❌ resolveOffer: \(error)")
        }
    }

    /// Dismiss the issuance overlay; reload lists on the "done" path (android onDone vs onCancel).
    func finishIssuance(reload: Bool) {
        issuingOffer = nil
        if reload { Task { await refresh() } }
    }

    /// Dismiss the presentation overlay; reload lists on the "done" path (a used one-time credential
    /// instance may have changed).
    func finishPresentation(reload: Bool) {
        presentingSession = nil
        if reload { Task { await refresh() } }
    }

    /// Delete a credential from the wallet, then refresh (android document-detail delete).
    func delete(_ id: CredentialId) async {
        do {
            try await wallet.credentials.delete(id)
            LogStore.shared.log("Deleted credential \(id.value)")
        } catch {
            LogStore.shared.log("❌ delete: \(error)")
        }
        await refresh()
    }

    /// Factory-reset the demo wallet: erase every credential (keys + keychain items), persisted activity,
    /// and the debug log (android Settings "Reset wallet"). Keys in the Secure Enclave go with their
    /// credential; onboarding/PIN are Phase 6, so there's nothing else to clear yet.
    func reset() async {
        for cred in credentials {
            try? await wallet.credentials.delete(cred.id)
        }
        await DemoWallet.txStore.clear()
        LogStore.shared.clear()
        LogStore.shared.log("Wallet reset — all credentials and activity erased")
        await refresh()
    }
}
