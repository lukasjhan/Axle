import AppleCore // TransactionLogEntry (re-exported)
import SwiftUI
import Wallet

// Shared UI building blocks — a port of android `ui/components/Components.kt` plus the reused rows from
// `DocumentRow.kt` / `HomeScreen.kt`. Fonts map onto the android `WalletTypography` slots via `WalletFont`.
// Names that would collide with the issuance-flow pieces in `IssueView.swift` (`InfoRow`, `TrustBadge`) are
// prefixed here (`WalletInfoRow`, `TrustPill`).

// MARK: - Card & primitives

/// The standard white, rounded, hairline-bordered card the whole UI is built from (android `WalletCard`).
struct WalletCard<Content: View>: View {
    private let padding: EdgeInsets
    private let onTap: (() -> Void)?
    private let content: Content

    init(
        padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.onTap = onTap
        self.content = content()
    }

    var body: some View {
        let card = VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(WalletTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WalletTheme.cardBorder, lineWidth: 1))

        if let onTap {
            Button(action: onTap) { card }.buttonStyle(.plain)
        } else {
            card
        }
    }
}

extension EdgeInsets {
    /// Zero padding — for cards that hold their own padded rows (with dividers).
    static let flush = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

/// A rounded pill/chip (android `Pill`).
struct Pill: View {
    let text: String
    var bg: Color
    var fg: Color
    var border: Color? = nil

    var body: some View {
        Text(text)
            .font(WalletFont.labelSmall)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(bg, in: Capsule())
            .overlay { if let border { Capsule().strokeBorder(border, lineWidth: 1) } }
            .foregroundStyle(fg)
    }
}

/// The green "Wallet secured" status pill from Home (android `SecuredPill`).
struct SecuredPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(WalletTheme.trust).frame(width: 7, height: 7)
            Text("Wallet secured").font(WalletFont.labelSmall)
        }
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(WalletTheme.trustBg, in: Capsule())
        .overlay { Capsule().strokeBorder(WalletTheme.trustBorder, lineWidth: 1) }
        .foregroundStyle(WalletTheme.trust)
    }
}

/// A trust/verification badge pill: green when trusted, amber-red when not (android `TrustBadge`).
struct TrustPill: View {
    let trusted: Bool
    var trustedText = "Verified"
    var untrustedText = "Not verified"

    var body: some View {
        if trusted {
            Pill(text: "✓ \(trustedText)", bg: WalletTheme.trustBg, fg: WalletTheme.trustDeep, border: WalletTheme.trustBorder)
        } else {
            Pill(text: "⚠ \(untrustedText)", bg: WalletTheme.dangerBg, fg: WalletTheme.danger, border: WalletTheme.danger.opacity(0.35))
        }
    }
}

/// Uppercase, letter-spaced section header (android `SectionLabel`).
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(WalletFont.sectionLabel)
            .tracking(0.8)
            .foregroundStyle(WalletTheme.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A gradient document tile with a short glyph (e.g. "ID", "DL") (android `DocTile`).
struct DocTile: View {
    let glyph: String
    let colors: [Color]
    var size: CGFloat = 42

    var body: some View {
        Text(glyph)
            .font(.custom("Manrope", size: 12).weight(.heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size / 3.5)
            )
    }
}

// MARK: - Rows

/// A shield-check row used in the trust panels (android `TrustRow`).
struct TrustRow: View {
    let label: String
    let value: String
    var ok = true

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 13))
                .foregroundStyle(ok ? WalletTheme.trust : WalletTheme.inkFaint)
            Text(label).font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.inkBody)
            Spacer()
            Text(value).font(WalletFont.bodyMediumStrong).foregroundStyle(ok ? WalletTheme.trust : WalletTheme.inkMuted)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// A key/value row with a bottom hairline divider (android `InfoRow`). Prefixed to avoid the issuance-flow
/// `InfoRow` in `IssueView.swift`.
struct WalletInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(label).font(WalletFont.bodySmall).foregroundStyle(WalletTheme.inkMuted)
                Spacer(minLength: 12)
                Text(value)
                    .font(WalletFont.bodyMediumStrong)
                    .foregroundStyle(valueColor ?? WalletTheme.ink)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            Rectangle().fill(WalletTheme.divider).frame(height: 1)
        }
    }
}

/// A tappable document list row (tile + title + issuer + validity chip). Shared by Home and Documents
/// (android `DocumentRow`).
struct DocumentRow: View {
    let cred: Credential
    let onTap: () -> Void

    var body: some View {
        WalletCard(padding: EdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13), onTap: onTap) {
            HStack(spacing: 13) {
                DocTile(glyph: credGlyph(cred), colors: credGradient(cred))
                VStack(alignment: .leading, spacing: 2) {
                    Text(credTitle(cred)).font(WalletFont.titleSmall).foregroundStyle(WalletTheme.ink).lineLimit(1)
                    if let issuer = cred.issuer?.displayName {
                        Text(issuer).font(WalletFont.bodySmall).foregroundStyle(WalletTheme.inkMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Pill(text: "Valid", bg: WalletTheme.trustBg, fg: WalletTheme.trustDeep)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WalletTheme.cardBorderStrong)
            }
        }
    }
}

/// The home hero card — a large gradient card featuring the primary credential (android `HeroCard`).
struct HeroCard: View {
    let cred: Credential
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(credKicker(cred).uppercased())
                        .font(WalletFont.labelSmall).tracking(0.6).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Pill(text: "eIDAS 2.0", bg: .white.opacity(0.12), fg: .white)
                }
                Spacer().frame(height: 26)
                Text(credTitle(cred)).font(WalletFont.titleMedium).foregroundStyle(.white)
                if let issuer = cred.issuer?.displayName {
                    Text(issuer).font(WalletFont.bodySmall).foregroundStyle(.white.opacity(0.75)).padding(.top, 3)
                }
                Spacer().frame(height: 18)
                HStack {
                    Text(validityLine(cred)).font(WalletFont.bodySmall).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    if cred.issuer?.trusted == true {
                        Text("✓ Verified").font(WalletFont.labelSmall).foregroundStyle(WalletTheme.gold)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: credGradient(cred), startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The Activity-tab row (arrow badge + counterparty + docs + status/time on the right). A 1:1 port of
/// android `ActivityScreen.ActivityCard`.
struct ActivityRow: View {
    let entry: TransactionLogEntry
    let onTap: () -> Void

    private var present: Bool { entry.type == .presentation }
    private var ok: Bool { entry.status == .success }

    var body: some View {
        WalletCard(padding: EdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13), onTap: onTap) {
            HStack(spacing: 12) {
                Text(present ? "↑" : "↓")
                    .font(WalletFont.titleSmall)
                    .foregroundStyle(present ? WalletTheme.brand : WalletTheme.trust)
                    .frame(width: 34, height: 34)
                    .background(present ? WalletTheme.brandSoftBg : WalletTheme.trustBg, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(counterparty).font(WalletFont.titleSmall).foregroundStyle(WalletTheme.ink).lineLimit(1)
                    Text(docsLabel).font(WalletFont.bodySmall).foregroundStyle(WalletTheme.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.status.rawValue) // "SUCCESS" / "ERROR" — uppercase, like android
                        .font(WalletFont.labelSmall)
                        .foregroundStyle(ok ? WalletTheme.trust : WalletTheme.danger)
                    Text(activityTime(entry.timestamp)).font(WalletFont.bodySmall).foregroundStyle(WalletTheme.inkFaint)
                }
            }
        }
    }

    private var counterparty: String {
        entry.relyingParty?.name ?? entry.relyingParty?.id ?? (present ? "Presentation" : "Issuance")
    }

    private var docsLabel: String {
        let names = entry.documents.map { $0.type ?? $0.format }.filter { !$0.isEmpty }
        if names.isEmpty { return "\(entry.documents.count) document(s)" }
        return names.joined(separator: ", ")
    }
}

/// The compact Home "Recent activity" row (arrow badge + title + "Status · relative time" + chevron). A
/// 1:1 port of android `HomeScreen.ActivityRow`, distinct from the Activity-tab card above.
struct HomeActivityRow: View {
    let entry: TransactionLogEntry
    let onTap: () -> Void

    private var present: Bool { entry.type == .presentation }
    private var issued: Bool { entry.type == .issuance }

    var body: some View {
        WalletCard(padding: EdgeInsets(top: 14, leading: 11, bottom: 14, trailing: 11), onTap: onTap) {
            HStack(spacing: 12) {
                Text(arrow)
                    .font(WalletFont.titleSmall)
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(badgeBg, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.ink).lineLimit(1)
                    Text("\(entry.status.rawValue.capitalized) · \(shortTime(entry.timestamp))")
                        .font(WalletFont.bodySmall).foregroundStyle(WalletTheme.inkFaint)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WalletTheme.cardBorderStrong)
            }
        }
    }

    private var arrow: String { present ? "↑" : issued ? "↓" : "✓" }
    private var tint: Color { present ? WalletTheme.brand : issued ? WalletTheme.trust : WalletTheme.inkMuted }
    private var badgeBg: Color { present ? WalletTheme.brandSoftBg : issued ? WalletTheme.trustBg : WalletTheme.screen }
    private var title: String {
        entry.relyingParty?.name ?? entry.relyingParty?.id ?? (issued ? "Credential issued" : present ? "Presentation" : "Verification")
    }
}

// MARK: - Empty state & overlays

/// The "add your first document" empty-state prompt (android `AddFirstDocument`).
struct AddFirstDocument: View {
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.plus").font(.system(size: 40)).foregroundStyle(WalletTheme.brand)
            Text("No documents yet").font(WalletFont.titleSmall).foregroundStyle(WalletTheme.ink)
            Text("Scan or paste an issuer offer to add your first document.")
                .font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.inkMuted).multilineTextAlignment(.center)
            Button(action: onScan) {
                Text("Scan QR").font(WalletFont.labelLarge).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(WalletTheme.brand, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(WalletTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WalletTheme.cardBorder, lineWidth: 1))
    }
}

/// A round icon button (back / overflow) on a card-coloured circle (android `CircleIcon`).
struct CircleIconButton: View {
    let system: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WalletTheme.ink)
                .frame(width: 36, height: 36)
                .background(WalletTheme.card, in: Circle())
                .overlay(Circle().strokeBorder(WalletTheme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A full-screen blocking overlay with a spinner (android `BusyOverlay`).
struct BusyOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(message).font(WalletFont.bodyLarge)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .transition(.opacity)
    }
}

// MARK: - Formatting helpers

/// "Valid until <date>" from an issued credential's validity, or "" when unknown (android `validityLine`).
func validityLine(_ c: Credential) -> String {
    guard case let .issued(_, validity, _) = c.lifecycle, let until = validity?.validUntil else { return "" }
    return "Valid until \(until.formatted(date: .abbreviated, time: .omitted))"
}

/// A compact relative time ("now", "5m", "3h", "2d") (android `relTime`).
func shortTime(_ epochSeconds: Int64) -> String {
    let now = Int64(Date().timeIntervalSince1970)
    let diff = now - epochSeconds
    switch diff {
    case ..<60: return "now"
    case ..<3600: return "\(diff / 60)m"
    case ..<86400: return "\(diff / 3600)h"
    default: return "\(diff / 86400)d"
    }
}

/// Absolute timestamp for the activity/detail screens.
func absoluteTime(_ epochSeconds: Int64, style: Date.FormatStyle) -> String {
    Date(timeIntervalSince1970: TimeInterval(epochSeconds)).formatted(style)
}

private let activityTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, HH:mm"
    return f
}()

/// The Activity-tab timestamp — absolute "MMM d, HH:mm" (android `timeFmt`).
func activityTime(_ epochSeconds: Int64) -> String {
    activityTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
}
