import SwiftUI

// Flow-screen chrome (issue / present / proximity) styled to match android — brand palette + Manrope,
// replacing the native pieces the flows used before. `PrimaryButton` / `SecondaryButton` mirror
// `ui/components/Components.kt`; the top bar / footer / status views mirror the android flow screens.

/// Brand-blue call-to-action (android `PrimaryButton`).
struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WalletFont.labelLarge)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(enabled ? WalletTheme.brand : WalletTheme.cardBorderStrong, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// White, hairline-bordered secondary button (android `SecondaryButton`).
struct SecondaryButton: View {
    let title: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WalletFont.labelLarge)
                .foregroundStyle(tint ?? WalletTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(WalletTheme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WalletTheme.cardBorderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Custom top bar: a round back button + title (android IssueScreen / PresentScreen header).
struct FlowTopBar: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CircleIconButton(system: "chevron.left", action: onBack)
            Text(title).font(WalletFont.titleMedium).foregroundStyle(WalletTheme.ink)
            Spacer()
        }
    }
}

/// The bottom action footer: secondary + primary side by side (android flow `Footer`).
struct FlowFooter: View {
    let primaryTitle: String
    var primaryEnabled = true
    let onPrimary: () -> Void
    var secondaryTitle: String? = nil
    var onSecondary: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let secondaryTitle, let onSecondary {
                SecondaryButton(title: secondaryTitle, action: onSecondary).frame(maxWidth: .infinity)
                PrimaryButton(title: primaryTitle, enabled: primaryEnabled, action: onPrimary).frame(maxWidth: .infinity)
            } else {
                PrimaryButton(title: primaryTitle, enabled: primaryEnabled, action: onPrimary)
            }
        }
        .padding(.top, 12)
    }
}

/// Centered loading state: brand spinner + title + subtitle (android `Loading`).
struct FlowLoading: View {
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ProgressView().tint(WalletTheme.brand).controlSize(.large)
            Spacer().frame(height: 20)
            Text(title).font(WalletFont.titleMedium).foregroundStyle(WalletTheme.ink)
            if !subtitle.isEmpty {
                Spacer().frame(height: 8)
                Text(subtitle).font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.inkMuted).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Centered terminal state: a coloured badge + title + subtitle + one primary button (android
/// `SuccessStep` / `FailedStep`).
struct FlowResult: View {
    enum Kind { case success, failure }
    let kind: Kind
    let title: String
    var subtitle: String = ""
    let buttonTitle: String
    let onButton: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(kind == .success ? WalletTheme.trustBg : WalletTheme.dangerBg).frame(width: 84, height: 84)
                if kind == .success {
                    Image(systemName: "checkmark").font(.system(size: 36, weight: .bold)).foregroundStyle(WalletTheme.trust)
                } else {
                    Text("!").font(WalletFont.titleLarge).foregroundStyle(WalletTheme.danger)
                }
            }
            Spacer().frame(height: 20)
            Text(title)
                .font(kind == .success ? WalletFont.titleLarge : WalletFont.titleMedium)
                .foregroundStyle(WalletTheme.ink)
            if !subtitle.isEmpty {
                Spacer().frame(height: 8)
                Text(subtitle).font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.inkMuted).multilineTextAlignment(.center)
            }
            Spacer().frame(height: 28)
            PrimaryButton(title: buttonTitle, action: onButton)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A short muted note line (android's inline `Text(..., bodySmall, inkMuted)` hints).
struct FlowNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(WalletFont.bodySmall).foregroundStyle(WalletTheme.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
