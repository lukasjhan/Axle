import Foundation
import Observation
import Wallet

/// App-level coordinator — the iOS counterpart of android `WalletRoot`'s URI routing and overlay state.
/// Scans and deep links both funnel through `handleURI`, which dispatches by scheme exactly like the
/// android `handleUri`: offer schemes resolve an offer (opening the issuance flow); VP schemes start a
/// presentation (Phase 3 step 2).
@MainActor
@Observable
final class WalletModel {
    /// Full-screen blocking overlay message (android `BusyOverlay`); nil when idle.
    var busy: String?
    /// Non-nil drives the issuance flow overlay (android `issuing`).
    var issuingOffer: CredentialOffer?
    /// Bumped on the "done" path so credential lists reload and show the new document (android `refreshKey`).
    var reloadToken = 0

    let wallet = DemoWallet.shared

    static let offerSchemes: Set<String> = ["openid-credential-offer", "haip-vci"]
    static let vpSchemes: Set<String> = ["openid4vp", "eudi-openid4vp", "mdoc-openid4vp", "haip-vp"]

    func handleURI(_ uri: String, source: String) {
        let scheme = uri.components(separatedBy: "://").first?.lowercased() ?? ""
        if Self.offerSchemes.contains(scheme) {
            Task { await resolveOffer(uri) }
        } else if Self.vpSchemes.contains(scheme) {
            // Remote presentation (OpenID4VP) — Phase 3 step 2.
        }
        // else: unrecognized scheme — ignore, matching android's no-op + log.
    }

    private func resolveOffer(_ uri: String) async {
        busy = "Resolving offer…"
        defer { busy = nil }
        issuingOffer = try? await wallet.issuance.resolveOffer(uri)
    }

    /// Dismiss the issuance overlay; reload lists only on the "done" path (android onDone vs onCancel).
    func finishIssuance(reload: Bool) {
        issuingOffer = nil
        if reload { reloadToken += 1 }
    }
}
