import SwiftUI
import UIKit
import Wallet
import WalletAPI // CredentialId.value

/// The Documents tab — every credential, most-recently-used first, with an add menu. Mirrors android
/// `DocumentsScreen`. Tapping a row pushes the document detail.
struct DocumentsView: View {
    @Environment(WalletModel.self) private var model
    @State private var path: [WalletRoute] = []

    private var ordered: [Credential] { model.credentials.byRecentUse(model.transactions) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if ordered.isEmpty {
                        AddFirstDocument { model.showScanner = true }
                    } else {
                        ForEach(ordered, id: \.id.value) { cred in
                            DocumentRow(cred: cred) { path.append(.document(cred.id)) }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }
            .walletScreenBackground()
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { model.showScanner = true } label: {
                            Label("Scan QR", systemImage: "qrcode.viewfinder")
                        }
                        Button {
                            if let text = UIPasteboard.general.string { model.handleURI(text, source: "Pasted") }
                        } label: {
                            Label("Paste offer or request", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .walletRouteDestinations(model)
        }
    }
}
