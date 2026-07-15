import SwiftUI
import Wallet
import WalletAPI // CredentialFormat cases

/// The document detail — gradient card, trust panel (credential signature + issuer registration), and the
/// credential's claims (sensitive values masked behind a reveal toggle) plus admin metadata. Mirrors
/// android `DocumentDetailScreen`. Proximity present (mDL) arrives with `AppleProximity` (Phase 4).
struct DocumentDetailView: View {
    let cred: Credential

    @Environment(WalletModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reveal = false
    @State private var confirmDelete = false

    private var claims: [Claim] {
        if case let .issued(claims, _, _) = cred.lifecycle { return claims }
        return []
    }
    private var personal: [Claim] { claims.filter { $0.category != .metadata } }
    private var metadata: [Claim] { claims.filter { $0.category == .metadata } }
    private var hasSensitive: Bool { claims.contains { isSensitive($0.path) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topBar
                gradientCard
                trustPanel
                if !personal.isEmpty {
                    SectionLabel("Claims")
                    claimsCard(personal)
                }
                if !metadata.isEmpty {
                    SectionLabel("Metadata")
                    claimsCard(metadata)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
        }
        .walletScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete \(credTitle(cred))?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await model.delete(cred.id); dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the credential from this device. You can be issued a new one later.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            CircleIconButton(system: "chevron.left") { dismiss() }
            Text(credTitle(cred)).font(.headline).foregroundStyle(WalletTheme.ink)
            Spacer()
            if hasSensitive {
                CircleIconButton(system: reveal ? "eye.slash" : "eye") { reveal.toggle() }
            }
            Menu {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete document", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WalletTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(WalletTheme.card, in: Circle())
                    .overlay(Circle().strokeBorder(WalletTheme.cardBorder, lineWidth: 1))
            }
        }
    }

    private var gradientCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(credKicker(cred).uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Pill(text: credFormatLabel(cred), bg: .white.opacity(0.12), fg: .white)
            }
            Spacer().frame(height: 22)
            Text(credTitle(cred)).font(.title3.weight(.semibold)).foregroundStyle(.white)
            if let issuer = cred.issuer?.displayName {
                Text(issuer).font(.caption).foregroundStyle(.white.opacity(0.75)).padding(.top, 3)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: credGradient(cred), startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private var trustPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Trust")
            WalletCard(padding: .flush) {
                TrustRow(label: "Credential signature", value: trustText(cred.issuer?.trusted), ok: cred.issuer?.trusted == true)
                Rectangle().fill(WalletTheme.divider).frame(height: 1)
                TrustRow(label: "Issuer registration", value: trustText(cred.issuer?.registered), ok: cred.issuer?.registered == true)
            }
        }
    }

    private func claimsCard(_ items: [Claim]) -> some View {
        WalletCard(padding: .flush) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, claim in
                WalletInfoRow(label: claimLabel(claim.path), value: displayValue(claim))
            }
        }
    }

    /// The SDK-rendered claim value, masked when sensitive and not revealed. Computed outside the
    /// ViewBuilder so the ternary isn't confused with SwiftUI's `View.mask`.
    private func displayValue(_ claim: Claim) -> String {
        let raw = claim.value.display()
        return (isSensitive(claim.path) && !reveal) ? maskSensitive(raw) : raw
    }

    // ── helpers (android trustText / claimLabel / isSensitive / mask) ──

    private func trustText(_ flag: Bool?) -> String {
        switch flag {
        case .some(true): return "Trusted"
        case .some(false): return "Not verified"
        case .none: return "Not checked"
        }
    }

    /// mdoc claim paths start with the namespace (same for every element) — drop it for readability.
    private func claimLabel(_ path: [String]) -> String {
        var p = path
        if case .msoMdoc = cred.format, p.count > 1 { p = Array(p.dropFirst()) }
        return p.map { seg in
            let spaced = seg.replacingOccurrences(of: "_", with: " ")
            return spaced.prefix(1).uppercased() + spaced.dropFirst()
        }.joined(separator: " › ")
    }
}

private let sensitiveKeys = ["number", "identifier", "birth", "national", "iban", "administrative", "document", "passport", "ssn", "tax"]

private func isSensitive(_ path: [String]) -> Bool {
    guard let key = path.last?.lowercased() else { return false }
    return sensitiveKeys.contains { key.contains($0) }
}

private func maskSensitive(_ v: String) -> String {
    String(v.map { $0.isLetter || $0.isNumber ? "•" : $0 })
}
