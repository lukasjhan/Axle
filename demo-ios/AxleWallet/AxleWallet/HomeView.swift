import AppleCore // TransactionLogEntry (re-exported)
import SwiftUI
import UIKit
import Wallet
import WalletAPI // CredentialId.value

/// The Home tab — greeting, a hero credential, quick actions, and previews of Documents and Recent
/// activity with "See all" links that switch tabs. Mirrors android `HomeScreen`.
struct HomeView: View {
    @Environment(WalletModel.self) private var model
    @State private var path: [WalletRoute] = []
    @State private var showReader = false
    @State private var showProximity = false

    private var ordered: [Credential] { model.credentials.byRecentUse(model.transactions) }
    private var hero: Credential? { ordered.first { credIsPid($0) } ?? ordered.first }
    private var rest: [Credential] { ordered.filter { $0.id.value != hero?.id.value } }
    private var recent: [TransactionLogEntry] { Array(model.transactions.prefix(3)) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let hero {
                        HeroCard(cred: hero) { path.append(.document(hero.id)) }
                        quickActions
                    } else {
                        AddFirstDocument { model.showScanner = true }
                    }

                    if !rest.isEmpty {
                        section(title: "Documents", action: "See all") { model.selectedTab = .documents } content: {
                            ForEach(rest.prefix(3), id: \.id.value) { cred in
                                DocumentRow(cred: cred) { path.append(.document(cred.id)) }
                            }
                        }
                    }

                    if !recent.isEmpty {
                        section(title: "Recent activity", action: "See all") { model.selectedTab = .activity } content: {
                            ForEach(recent, id: \.id) { entry in
                                ActivityRow(entry: entry) { path.append(.transaction(entry.id)) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            .walletScreenBackground()
            .navigationBarHidden(true)
            .walletRouteDestinations(model)
        }
        .fullScreenCover(isPresented: $showReader) {
            ReaderView { showReader = false }
        }
        .fullScreenCover(isPresented: $showProximity) {
            ProximityHolderView { showProximity = false }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting()).font(.subheadline).foregroundStyle(WalletTheme.inkMuted)
                Text(holderName()).font(.title2.weight(.bold)).foregroundStyle(WalletTheme.ink)
            }
            Spacer()
            SecuredPill()
        }
    }

    private var quickActions: some View {
        // Scan (issuer offer / verifier request), Present (show a document in person over BLE), Reader
        // (verify someone else's document). Paste lives in the Documents "+" menu. Mirrors android's trio.
        HStack(spacing: 10) {
            QuickAction(label: "Scan", system: "qrcode.viewfinder", primary: true) { model.showScanner = true }
            QuickAction(label: "Present", system: "dot.radiowaves.left.and.right", primary: false) { showProximity = true }
            QuickAction(label: "Reader", system: "doc.text.viewfinder", primary: false) { showReader = true }
        }
    }

    @ViewBuilder
    private func section(
        title: String,
        action: String?,
        onAction: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline).foregroundStyle(WalletTheme.ink)
                Spacer()
                if let action {
                    Button(action: onAction) {
                        Text(action).font(.subheadline.weight(.medium)).foregroundStyle(WalletTheme.brand)
                    }
                }
            }
            content()
        }
    }

    // ── helpers (android greeting / holderName) ──

    private func greeting() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// Best-effort holder name from a PID credential's given/family name claims.
    private func holderName() -> String {
        for cred in model.credentials {
            guard case let .issued(claims, _, _) = cred.lifecycle else { continue }
            let given = claims.first { $0.path.last?.caseInsensitiveCompare("given_name") == .orderedSame }?.value.display()
            let family = claims.first { $0.path.last?.caseInsensitiveCompare("family_name") == .orderedSame }?.value.display()
            let name = [given, family].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return "Your wallet"
    }
}

/// A Home quick-action button — brand-filled (primary) or bordered (secondary).
private struct QuickAction: View {
    let label: String
    let system: String
    let primary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: system).font(.system(size: 18))
                Text(label).font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(primary ? .white : WalletTheme.ink)
            .background(primary ? WalletTheme.brand : WalletTheme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(WalletTheme.cardBorderStrong, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
