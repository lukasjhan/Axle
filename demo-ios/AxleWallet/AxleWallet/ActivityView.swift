import AppleCore // TransactionLogEntry (re-exported)
import SwiftUI

/// The Activity tab — the transaction log (issuances + presentations), most recent first, under an inline
/// title (android `ActivityScreen`). Tapping a row pushes the transaction detail.
struct ActivityView: View {
    @Environment(WalletModel.self) private var model
    @State private var path: [WalletRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Activity").font(WalletFont.titleLarge).foregroundStyle(WalletTheme.ink)
                    if model.transactions.isEmpty {
                        Text("Nothing yet — your issuances and presentations will appear here.")
                            .font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(model.transactions, id: \.id) { entry in
                            ActivityRow(entry: entry) { path.append(.transaction(entry.id)) }
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
