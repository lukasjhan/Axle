import AppleCore // TransactionLogEntry & friends (re-exported)
import SwiftUI

/// The transaction detail — header, counterparty (relying party or issuer), purpose/entitlements, and the
/// data shared/received with per-document claims. Mirrors android `TransactionDetailScreen`.
struct TransactionDetailView: View {
    let entry: TransactionLogEntry

    @Environment(\.dismiss) private var dismiss

    private var present: Bool { entry.type == .presentation }
    private var ok: Bool { entry.status == .success }
    private var rp: RelyingParty? { entry.relyingParty }

    private var title: String {
        rp?.name ?? rp?.id ?? entry.issuerName ?? entry.issuer.map(hostOf)
            ?? (present ? "Presentation" : "Credential issued")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topBar
                headerCard
                counterparty
                documentsSection
                if let error = entry.error {
                    WalletCard { Text(error).font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.danger) }
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
        }
        .walletScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            CircleIconButton(system: "chevron.left") { dismiss() }
            Text(present ? "Shared" : "Issued").font(WalletFont.titleMedium).foregroundStyle(WalletTheme.ink)
            Spacer()
        }
    }

    private var headerCard: some View {
        WalletCard {
            HStack(spacing: 13) {
                Text(present ? "↑" : "↓")
                    .font(WalletFont.titleMedium)
                    .foregroundStyle(present ? WalletTheme.brand : WalletTheme.trust)
                    .frame(width: 44, height: 44)
                    .background(present ? WalletTheme.brandSoftBg : WalletTheme.trustBg, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(WalletFont.titleSmall).foregroundStyle(WalletTheme.ink)
                    Text(fullTime(entry.timestamp)).font(WalletFont.bodySmall).foregroundStyle(WalletTheme.inkMuted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(entry.status.rawValue.capitalized)
                        .font(WalletFont.labelSmall)
                        .foregroundStyle(ok ? WalletTheme.trust : WalletTheme.danger)
                    if let transport = entry.transport {
                        Pill(text: transportLabel(transport), bg: WalletTheme.screen, fg: WalletTheme.inkMuted)
                    }
                }
            }
        }
    }

    @ViewBuilder private var counterparty: some View {
        if present, let rp {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Relying party")
                WalletCard(padding: .flush) {
                    if let name = rp.name { WalletInfoRow(label: "Name", value: name) }
                    WalletInfoRow(label: "Identifier", value: rp.id)
                    if let subject = rp.subject, !subject.isEmpty { WalletInfoRow(label: "Registered as", value: subject) }
                    TrustRow(label: "Signed request", value: rp.trusted ? "Verified" : "Not verified", ok: rp.trusted)
                    if let attested = rp.attested {
                        TrustRow(label: "Registration (WRPRC)", value: attested ? "Verified by registrar" : "Self-declared", ok: attested)
                    }
                    if let statusValid = rp.statusValid {
                        WalletInfoRow(label: "Registration status", value: statusValid ? "Valid" : "Revoked",
                                      valueColor: statusValid ? nil : WalletTheme.danger)
                    }
                    if let intermediary = rp.intermediaryName { WalletInfoRow(label: "Via intermediary", value: intermediary) }
                }
            }

            let purpose = purposeText(rp.purpose)
            if !purpose.isEmpty || rp.outOfScope != nil {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Purpose")
                    WalletCard {
                        HStack(spacing: 10) {
                            Text(purpose.isEmpty ? "Attribute request" : purpose)
                                .font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.ink)
                            Spacer()
                            if let outOfScope = rp.outOfScope {
                                TrustPill(trusted: !outOfScope, trustedText: "In scope", untrustedText: "Out of scope")
                            }
                        }
                    }
                }
            }

            if !rp.entitlements.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Entitlements")
                    WalletCard(padding: .flush) {
                        ForEach(Array(rp.entitlements.enumerated()), id: \.offset) { i, ent in
                            if i > 0 { Rectangle().fill(WalletTheme.divider).frame(height: 1) }
                            Text(ent).font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.inkBody)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 13)
                        }
                    }
                }
            }
        } else if !present {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Issuer")
                WalletCard(padding: .flush) {
                    WalletInfoRow(label: "Issuer", value: entry.issuerName ?? entry.issuer.map(hostOf) ?? "—")
                    if let issuer = entry.issuer { WalletInfoRow(label: "Identifier", value: hostOf(issuer)) }
                    if let registered = entry.issuerRegistered {
                        TrustRow(label: "Registered issuer", value: registered ? "Yes" : "No", ok: registered)
                    }
                }
            }
        }
    }

    @ViewBuilder private var documentsSection: some View {
        if !entry.documents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(present ? "Data shared" : "Data received")
                ForEach(Array(entry.documents.enumerated()), id: \.offset) { _, doc in
                    WalletCard(padding: .flush) {
                        Text(doc.type ?? doc.format).font(WalletFont.titleSmall).foregroundStyle(WalletTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        Rectangle().fill(WalletTheme.divider).frame(height: 1)
                        if doc.claims.isEmpty {
                            WalletInfoRow(label: "Claims", value: "—")
                        } else {
                            ForEach(Array(doc.claims.enumerated()), id: \.offset) { _, claim in
                                WalletInfoRow(label: claimLabel(doc.format, claim.path), value: claim.value ?? "Disclosed")
                            }
                        }
                    }
                }
            }
        }
    }

    // ── helpers (android transportLabel / purposeText / claimLabel) ──

    private func transportLabel(_ t: TransactionTransport) -> String {
        t == .proximity ? "In person" : "Online"
    }

    /// Pick the purpose text in the device language, falling back to the first entry.
    private func purposeText(_ purpose: [LocalizedText]) -> String {
        if purpose.isEmpty { return "" }
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return (purpose.first { $0.lang.lowercased().hasPrefix(lang.lowercased()) } ?? purpose[0]).value
    }

    private func claimLabel(_ format: String, _ path: [String]) -> String {
        var p = path
        if format.lowercased().contains("mdoc"), p.count > 1 { p = Array(p.dropFirst()) }
        return p.map { seg in
            let spaced = seg.replacingOccurrences(of: "_", with: " ")
            return spaced.prefix(1).uppercased() + spaced.dropFirst()
        }.joined(separator: " › ")
    }

    private func fullTime(_ epochSeconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute())
    }
}
