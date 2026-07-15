import AppleCore // TransactionLogEntry (re-exported)
import SwiftUI
import Wallet
import WalletAPI // CredentialId

/// A value-based navigation target for the per-tab `NavigationStack`s. Both detail screens resolve their
/// subject from the model's single snapshot, so any tab can push either detail by id.
enum WalletRoute: Hashable {
    case document(CredentialId)
    case transaction(String)
}

/// The four bottom tabs (android `Routes` main tabs).
enum WalletTab: Hashable { case home, documents, activity, settings }

/// The wallet's root — the iOS counterpart of android `WalletRoot`. A 4-tab bar (Home / Documents /
/// Activity / Settings; Debug is pushed from Settings), with the issuance and presentation flows presented
/// as full-screen covers and a blocking busy overlay, all driven by one `WalletModel`.
struct WalletHome: View {
    @State private var model = WalletModel()

    var body: some View {
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: WalletTab.home) {
                HomeView()
            }
            Tab("Documents", systemImage: "creditcard.fill", value: WalletTab.documents) {
                DocumentsView()
            }
            Tab("Activity", systemImage: "clock.arrow.circlepath", value: WalletTab.activity) {
                ActivityView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: WalletTab.settings) {
                SettingsView()
            }
        }
        .tint(WalletTheme.brand)
        .environment(model)
        .preferredColorScheme(.light) // the design is a fixed light theme (android parity)
        .task { await model.start() }
        .onOpenURL { model.handleURI($0.absoluteString, source: "Opened link") }
        .sheet(isPresented: $model.showScanner) {
            ScannerSheet { model.handleURI($0, source: "Scanned") }
        }
        .fullScreenCover(isPresented: issuingBinding) {
            if let offer = model.issuingOffer {
                IssueView(
                    offer: offer,
                    onDone: { model.finishIssuance(reload: true) },
                    onCancel: { model.finishIssuance(reload: false) }
                )
            }
        }
        .fullScreenCover(isPresented: presentingBinding) {
            if let session = model.presentingSession {
                PresentView(
                    session: session,
                    onDone: { model.finishPresentation(reload: true) },
                    onCancel: { model.finishPresentation(reload: false) }
                )
            }
        }
        .overlay {
            if let busy = model.busy { BusyOverlay(message: busy) }
        }
    }

    private var issuingBinding: Binding<Bool> {
        Binding(get: { model.issuingOffer != nil }, set: { if !$0 { model.issuingOffer = nil } })
    }

    private var presentingBinding: Binding<Bool> {
        Binding(get: { model.presentingSession != nil }, set: { if !$0 { model.presentingSession = nil } })
    }
}

/// Resolves a `WalletRoute` into its detail screen from the model's snapshot. Attached to each tab's
/// `NavigationStack` so Home/Documents/Activity can all push details.
struct WalletRouteDestination: ViewModifier {
    let model: WalletModel

    func body(content: Content) -> some View {
        content.navigationDestination(for: WalletRoute.self) { route in
            switch route {
            case let .document(id):
                if let cred = model.credentials.first(where: { $0.id == id }) {
                    DocumentDetailView(cred: cred)
                }
            case let .transaction(id):
                if let entry = model.transactions.first(where: { $0.id == id }) {
                    TransactionDetailView(entry: entry)
                }
            }
        }
    }
}

extension View {
    func walletRouteDestinations(_ model: WalletModel) -> some View {
        modifier(WalletRouteDestination(model: model))
    }
}
