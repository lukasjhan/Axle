import AppleProximity
import Foundation
import SwiftUI
import Wallet

/// Reader/verifier-side ISO 18013-5 proximity — the iOS counterpart of android `ProximityReaderScreen`.
/// Scans the holder's QR DeviceEngagement, connects over BLE as the central, requests the PID elements, and
/// renders the verified result.
struct ReaderView: View {
    let onClose: () -> Void

    private let wallet = DemoWallet.shared
    @State private var phase: Phase = .idle
    @State private var showScanner = false
    @State private var results: [ReaderResultDoc] = []
    @State private var errorMessage: String?
    @State private var transport: BleCentralTransport?

    enum Phase { case idle, connecting, reading, results, failed }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .walletScreenBackground()
                .navigationTitle("Reader")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { close() } }
                }
                .sheet(isPresented: $showScanner) {
                    ScannerSheet { scanned in Task { await read(scanned) } }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle:
            idleStep
        case .connecting:
            CenteredStatus(system: nil, title: "Connecting…", subtitle: "Pairing with the wallet over Bluetooth.", showsSpinner: true)
        case .reading:
            CenteredStatus(system: nil, title: "Reading…", subtitle: "Requesting and verifying the document.", showsSpinner: true)
        case .results:
            resultsStep
        case .failed:
            CenteredStatus(system: "exclamationmark.triangle.fill", title: "Couldn't read", subtitle: errorMessage ?? "The read failed.", tint: .red, button: ("Try again", { phase = .idle }))
        }
    }

    private var idleStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "qrcode.viewfinder").font(.system(size: 56)).foregroundStyle(WalletTheme.brand)
            Text("Scan a wallet's code").font(.title3.weight(.semibold)).foregroundStyle(WalletTheme.ink)
            Text("Ask the holder to show their in-person sharing QR, then scan it to read and verify their document.")
                .font(.subheadline).foregroundStyle(WalletTheme.inkMuted).multilineTextAlignment(.center)
            Spacer()
            Button { showScanner = true } label: {
                Label("Scan holder QR", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(WalletTheme.brand).padding()
        }
        .padding()
    }

    private var resultsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(results.enumerated()), id: \.offset) { _, doc in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(prettyConfig(doc.docType)).font(.headline).foregroundStyle(WalletTheme.ink)
                            Spacer()
                            TrustPill(trusted: doc.deviceAuthenticated, trustedText: "Verified", untrustedText: "Unverified")
                        }
                        WalletCard(padding: .flush) {
                            if doc.claims.isEmpty {
                                WalletInfoRow(label: "Claims", value: "—")
                            } else {
                                ForEach(Array(doc.claims.enumerated()), id: \.offset) { _, claim in
                                    WalletInfoRow(label: label(claim.element), value: claim.value)
                                }
                            }
                        }
                    }
                }
                Button { phase = .idle; results = [] } label: {
                    Label("Scan another", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large).tint(WalletTheme.brand)
            }
            .padding()
        }
    }

    private func label(_ element: String) -> String {
        let spaced = element.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    // MARK: - Behavior

    private func read(_ scanned: String) async {
        guard let engagement = Self.decodeEngagement(scanned) else {
            errorMessage = "That QR isn't an in-person sharing code."
            phase = .failed
            return
        }
        phase = .connecting
        do {
            let t = try BleCentralTransport(engagement: engagement)
            transport = t
            try await t.connect()
            phase = .reading
            let verified = try await wallet.reader.read(transport: t, engagement: engagement, documents: MdocReaderRequests.pid())
            results = MdocReaderRequests.flatten(verified)
            phase = .results
        } catch {
            errorMessage = String(describing: error)
            phase = .failed
        }
        if let transport { await transport.close(); self.transport = nil }
    }

    private func close() {
        if let transport { Task { await transport.close() } }
        onClose()
    }

    /// Parses an ISO 18013-5 `mdoc:`-prefixed QR into the DeviceEngagement bytes (base64url).
    private static func decodeEngagement(_ qr: String) -> [UInt8]? {
        guard qr.hasPrefix("mdoc:") else { return nil }
        var b64 = String(qr.dropFirst("mdoc:".count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return [UInt8](data)
    }
}
