import SwiftUI

/// The app root — gates the wallet behind first-run onboarding, the wallet-assembly splash, and the
/// auto-lock. The wallet assembles asynchronously on launch (it fetches trust anchors), so `WalletHome`
/// (and `DemoWallet.shared`) is only built once `boot()` finishes. `LockView` overlays the live wallet on
/// re-lock, also masking content in the app switcher.
struct RootView: View {
    @State private var appLock = AppLock()
    @State private var walletReady = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .environment(appLock)
            .preferredColorScheme(.light)
            .task { WalletSecurity.syncSharedGroup(); await DemoWallet.boot(); walletReady = true }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { appLock.lock() }
            }
    }

    @ViewBuilder private var content: some View {
        if !appLock.onboarded {
            OnboardingView { appLock.completeOnboarding() }
        } else if !walletReady {
            SplashView()
        } else {
            ZStack {
                WalletHome()
                if appLock.locked { LockView { appLock.unlock() } }
            }
        }
    }
}

/// Shown while the wallet assembles (trust-anchor fetch on first launch).
struct SplashView: View {
    var body: some View {
        ZStack {
            WalletTheme.screen.ignoresSafeArea()
            VStack(spacing: 20) {
                Text("★").font(WalletFont.titleLarge).foregroundStyle(WalletTheme.gold)
                    .frame(width: 76, height: 76)
                    .background(LinearGradient(colors: DocGradients.pid, startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 22))
                ProgressView().tint(WalletTheme.brand)
                Text("Preparing your wallet…").font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.inkMuted)
            }
        }
    }
}
