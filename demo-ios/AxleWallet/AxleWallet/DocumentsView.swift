import SwiftUI
import Wallet
import WalletAPI // CredentialId.value

/// The Documents tab — every credential, most-recently-used first, under an inline title (android
/// `DocumentsScreen`). Tapping a row pushes the document detail. There is no add button here — scanning is
/// initiated from Home, matching android.
struct DocumentsView: View {
    @Environment(WalletModel.self) private var model
    @State private var path: [WalletRoute] = []

    private var ordered: [Credential] { model.credentials.byRecentUse(model.transactions) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Documents").font(WalletFont.titleLarge).foregroundStyle(WalletTheme.ink)
                    if ordered.isEmpty {
                        AddFirstDocument { model.showScanner = true }
                    } else {
                        ForEach(ordered, id: \.id.value) { cred in
                            DocumentRow(cred: cred) { path.append(.document(cred.id)) }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
            }
            .walletScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .walletRouteDestinations(model)
        }
    }
}
