import SwiftUI

/// The Settings tab — wallet facts plus developer tools (Debug log, Reset). Mirrors android
/// `SettingsScreen`; the proximity-sharing options arrive with `AppleProximity` (Phase 4).
struct SettingsView: View {
    @Environment(WalletModel.self) private var model
    @State private var resetConfirm = false

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Wallet")
                        WalletCard(padding: .flush) {
                            WalletInfoRow(label: "Security hardware", value: "Secure Enclave")
                            WalletInfoRow(label: "Trusted list", value: "Synced")
                            WalletInfoRow(label: "Version", value: version)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Developer")
                        WalletCard(padding: .flush) {
                            NavigationLink { DebugView() } label: {
                                settingRow("Debug log", trailing: "chevron.right", tint: WalletTheme.ink)
                            }
                            .buttonStyle(.plain)
                            Rectangle().fill(WalletTheme.divider).frame(height: 1)
                            Button { resetConfirm = true } label: {
                                settingRow("Reset wallet", trailing: nil, tint: WalletTheme.danger)
                            }
                            .buttonStyle(.plain)
                        }
                        Text("Reset erases all credentials and activity from this device. You can be issued new documents afterwards.")
                            .font(.caption).foregroundStyle(WalletTheme.inkMuted)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }
            .walletScreenBackground()
            .navigationTitle("Settings")
            .alert("Reset wallet?", isPresented: $resetConfirm) {
                Button("Reset", role: .destructive) { Task { await model.reset() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This erases all credentials and transaction history. Documents can be re-issued later.")
            }
        }
    }

    private func settingRow(_ label: String, trailing: String?, tint: Color) -> some View {
        HStack {
            Text(label).font(.body).foregroundStyle(tint)
            Spacer()
            if let trailing {
                Image(systemName: trailing).font(.caption.weight(.semibold)).foregroundStyle(WalletTheme.inkFaint)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}
