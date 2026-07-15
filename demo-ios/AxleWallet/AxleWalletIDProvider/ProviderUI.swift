import SwiftUI

// The DC API consent screen is our own SwiftUI (the OS just hosts the extension scene), so it uses the same brand
// design system as the app's presentation screens. The extension is a separate target and can't import the app,
// so the subset it needs is ported here 1:1 from the app's `Theme.swift` / `WalletComponents.swift` — same colors,
// Manrope type scale, and card / pill / row styling, so the consent looks identical to the in-app share screens.

enum WalletTheme {
    static let brand = Color(hex: 0x2555DB)
    static let screen = Color(hex: 0xF4F5F9)
    static let card = Color.white
    static let cardBorder = Color(hex: 0xE9EBF1)
    static let cardBorderStrong = Color(hex: 0xE4E7EC)
    static let divider = Color(hex: 0xF0F2F7)
    static let ink = Color(hex: 0x101828)
    static let inkBody = Color(hex: 0x344054)
    static let inkMuted = Color(hex: 0x667085)
    static let inkFaint = Color(hex: 0x98A2B3)
    static let trust = Color(hex: 0x12855F)
    static let trustDeep = Color(hex: 0x0E6B4C)
    static let trustBg = Color(hex: 0xE8F5EE)
    static let trustBorder = Color(hex: 0xC2E5D2)
    static let danger = Color(hex: 0xD92D20)
    static let dangerBg = Color(hex: 0xFEF3F2)
}

enum WalletFont {
    private static func manrope(_ size: CGFloat, _ weight: Font.Weight) -> Font { .custom("Manrope", size: size).weight(weight) }
    static let titleLarge = manrope(21, .heavy)
    static let titleMedium = manrope(16, .heavy)
    static let titleSmall = manrope(14, .bold)
    static let bodyMedium = manrope(13, .semibold)
    static let bodySmall = manrope(12, .medium)
    static let labelLarge = manrope(14, .bold)
    static let labelSmall = manrope(11, .bold)
    static let sectionLabel = manrope(11.5, .heavy)
    static let bodyMediumStrong = manrope(13, .bold)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// White, rounded, hairline-bordered container (app `WalletCard`).
struct WalletCard<Content: View>: View {
    private let padding: EdgeInsets
    private let content: Content
    init(padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16), @ViewBuilder content: () -> Content) {
        self.padding = padding; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(WalletTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WalletTheme.cardBorder, lineWidth: 1))
    }
}

extension EdgeInsets { static let flush = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0) }

struct Pill: View {
    let text: String; var bg: Color; var fg: Color; var border: Color?
    var body: some View {
        Text(text).font(WalletFont.labelSmall)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(bg, in: Capsule())
            .overlay { if let border { Capsule().strokeBorder(border, lineWidth: 1) } }
            .foregroundStyle(fg)
    }
}

/// Green when the reader chained to a trusted anchor, amber-red when not (app `TrustPill`).
struct TrustPill: View {
    let trusted: Bool
    var trustedText = "Verified"
    var untrustedText = "Unverified"
    var body: some View {
        if trusted {
            Pill(text: "✓ \(trustedText)", bg: WalletTheme.trustBg, fg: WalletTheme.trustDeep, border: WalletTheme.trustBorder)
        } else {
            Pill(text: "⚠ \(untrustedText)", bg: WalletTheme.dangerBg, fg: WalletTheme.danger, border: WalletTheme.danger.opacity(0.35))
        }
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(WalletFont.sectionLabel).tracking(0.8)
            .foregroundStyle(WalletTheme.inkFaint).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TrustRow: View {
    let label: String; let value: String; var ok = true
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 13))
                .foregroundStyle(ok ? WalletTheme.trust : WalletTheme.inkFaint)
            Text(label).font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.inkBody)
            Spacer()
            Text(value).font(WalletFont.bodyMediumStrong).foregroundStyle(ok ? WalletTheme.trust : WalletTheme.inkMuted)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

/// A disclosed-attribute row (checkmark + humanized element name), hairline-divided (app `WalletInfoRow`).
struct SharedAttributeRow: View {
    let label: String
    var last = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(WalletTheme.brand)
                Text(label).font(WalletFont.bodyMediumStrong).foregroundStyle(WalletTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if !last { Rectangle().fill(WalletTheme.divider).frame(height: 1) }
        }
    }
}

struct PrimaryButton: View {
    let title: String; var enabled = true; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(WalletFont.labelLarge).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(enabled ? WalletTheme.brand : WalletTheme.cardBorderStrong, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(WalletFont.labelLarge).foregroundStyle(WalletTheme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(WalletTheme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WalletTheme.cardBorderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Subtle informational footnote (app `FlowNote`).
struct FlowNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(WalletFont.bodySmall).foregroundStyle(WalletTheme.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
