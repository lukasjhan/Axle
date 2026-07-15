import AppleCore
import SwiftUI
import Wallet
import WalletTestKit

/// Phase-1/2 milestone screen: lists stored credentials via `wallet.credentials.list()`, plus a debug
/// action that qualifies the real Secure Enclave / Keychain adapters against the SDK's contract suites
/// on-device. The full Documents/Home/Activity/Settings UI (mirroring android `demo`) arrives in Phase 3.
struct ContentView: View {
    @State private var credentials: [Credential] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var contractResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                } else if let loadError {
                    ContentUnavailableView(
                        "Couldn't load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if credentials.isEmpty {
                    ContentUnavailableView(
                        "No documents yet",
                        systemImage: "doc.text",
                        description: Text("Issued credentials will appear here.")
                    )
                } else {
                    List(credentials, id: \.id) { credential in
                        DocumentRow(credential: credential)
                    }
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await runContractTests() }
                    } label: {
                        Image(systemName: "checkmark.seal")
                    }
                    .disabled(isTesting)
                    .accessibilityLabel("Test adapters")
                }
            }
            .alert("Adapter check", isPresented: showingResult) {
                Button("OK", role: .cancel) { contractResult = nil }
            } message: {
                Text(contractResult ?? "")
            }
        }
        .task { await load() }
    }

    private var showingResult: Binding<Bool> {
        Binding(get: { contractResult != nil }, set: { if !$0 { contractResult = nil } })
    }

    private func load() async {
        isLoading = true
        do {
            credentials = try await DemoWallet.shared.credentials.list()
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
        isLoading = false
    }

    /// Phase-2 on-device qualification: "adapter qualification = passing the shared contract suite."
    private func runContractTests() async {
        isTesting = true
        defer { isTesting = false }
        do {
            try await SecureAreaContract.verify(SecureEnclaveSecureArea())
            try await StorageDriverContract.verify(KeychainStorageDriver())
            contractResult = "✅ Secure Enclave + Keychain adapters pass the SDK contract suites."
        } catch {
            contractResult = "❌ \(error)"
        }
    }
}

private struct DocumentRow: View {
    let credential: Credential

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Text("\(claimCount) claims").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        credential.display?.name ?? credential.configurationId ?? "Credential"
    }

    private var subtitle: String? {
        credential.issuer?.displayName ?? credential.issuer?.url
    }

    private var claimCount: Int {
        if case let .issued(claims, _, _) = credential.lifecycle { return claims.count }
        return 0
    }
}

#Preview {
    ContentView()
}
