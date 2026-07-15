import AppleProximity
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import Wallet

/// Holder-side ISO 18013-5 proximity presentation over BLE — the iOS counterpart of android
/// `ProximityHolderDialog`. Advertises a per-session BLE service, shows the QR DeviceEngagement for the
/// reader to scan, then drives the `ProximityService.present` session through consent to a result.
struct ProximityHolderView: View {
    let onClose: () -> Void

    private let wallet = DemoWallet.shared
    @State private var phase: Phase = .starting
    @State private var qr: UIImage?
    @State private var request: ProximityRequest?
    @State private var errorMessage: String?
    @State private var transport: BlePeripheralTransport?
    @State private var session: ProximitySession?

    enum Phase { case starting, engaging, consent, sending, done, declined, failed }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WalletTheme.screen.ignoresSafeArea())
        .task { await run() }
        .onDisappear { teardown() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .starting:
            CenteredStatus(system: nil, title: "Starting Bluetooth…", subtitle: "Preparing in-person sharing.", showsSpinner: true)
        case .engaging:
            engagingStep
        case .consent:
            if let request { consentStep(request) }
        case .sending:
            CenteredStatus(system: nil, title: "Sharing…", subtitle: "Sending your document to the reader.", showsSpinner: true)
        case .done:
            CenteredStatus(system: "checkmark.circle.fill", title: "Shared", subtitle: "Your document was presented in person.", tint: .green, button: ("Done", onClose))
        case .declined:
            CenteredStatus(system: "hand.raised.fill", title: "Declined", subtitle: "Nothing was shared.", tint: .orange, button: ("Close", onClose))
        case .failed:
            CenteredStatus(system: "exclamationmark.triangle.fill", title: "Couldn't share", subtitle: errorMessage ?? "The proximity session failed.", tint: .red, button: ("Close", onClose))
        }
    }

    private var engagingStep: some View {
        VStack(spacing: 20) {
            Text("Show this to the reader").font(.title3.weight(.semibold)).foregroundStyle(WalletTheme.ink)
            Text("The verifier scans this code to connect over Bluetooth.")
                .font(.subheadline).foregroundStyle(WalletTheme.inkMuted).multilineTextAlignment(.center)
            Group {
                if let qr {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 280)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(WalletTheme.cardBorder, lineWidth: 1))
                } else {
                    ProgressView()
                }
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for the reader…").font(.footnote).foregroundStyle(WalletTheme.inkMuted)
            }
            Spacer()
            Button(role: .cancel) { cancel() } label: { Text("Cancel").frame(maxWidth: .infinity) }
                .controlSize(.large).padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func consentStep(_ request: ProximityRequest) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sharing request").font(.title2.weight(.bold)).foregroundStyle(WalletTheme.ink)

                    SectionLabel("Reader")
                    WalletCard {
                        HStack {
                            Text(request.reader.commonName ?? "Unverified reader")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(WalletTheme.ink)
                            Spacer()
                            TrustPill(trusted: request.reader.trusted, trustedText: "Verified", untrustedText: "Unverified")
                        }
                    }

                    SectionLabel("Requested")
                    ForEach(Array(request.documents.enumerated()), id: \.offset) { _, doc in
                        WalletCard(padding: .flush) {
                            Text(prettyConfig(doc.docType)).font(.subheadline.weight(.semibold)).foregroundStyle(WalletTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                            Rectangle().fill(WalletTheme.divider).frame(height: 1)
                            ForEach(elementLabels(doc), id: \.self) { label in
                                WalletInfoRow(label: label, value: doc.candidates.isEmpty ? "Not held" : "Will share")
                            }
                        }
                    }
                    if !request.satisfiable {
                        NoteText("You don't hold the requested document, so nothing can be shared.")
                    }
                }
                .padding()
            }
            Footer(
                primary: "Share",
                secondary: "Decline",
                primaryEnabled: request.satisfiable,
                onPrimary: { session?.respond(ProximitySelection.auto(request)) },
                onSecondary: { session?.decline() }
            )
        }
    }

    private func elementLabels(_ doc: RequestedDocumentView) -> [String] {
        doc.requestedElements.flatMap { _, els in els }.sorted().map { seg in
            let spaced = seg.replacingOccurrences(of: "_", with: " ")
            return spaced.prefix(1).uppercased() + spaced.dropFirst()
        }
    }

    // MARK: - Behavior

    private func run() async {
        guard transport == nil else { return } // task can re-fire; start once
        let t = BlePeripheralTransport()
        transport = t
        do {
            try await t.start()
        } catch {
            errorMessage = String(describing: error)
            phase = .failed
            return
        }
        let s = wallet.proximity.present(t)
        session = s
        for await state in s.states {
            switch state {
            case .generatingEngagement:
                phase = .starting
            case let .engagementReady(engagement, _):
                qr = Self.qrImage(mdocQR(engagement))
                phase = .engaging
            case let .requestReceived(req):
                request = req
                phase = .consent
            case .submitting:
                phase = .sending
            case .completed:
                phase = .done
                return
            case .declined:
                phase = .declined
                return
            case let .failed(error):
                errorMessage = String(describing: error)
                phase = .failed
                return
            }
        }
    }

    private func cancel() {
        session?.cancel()
        teardown()
        onClose()
    }

    private func teardown() {
        session?.cancel()
        if let transport { Task { await transport.close() } }
    }

    /// ISO 18013-5 QR payload: `mdoc:` + base64url(DeviceEngagement).
    private func mdocQR(_ engagement: [UInt8]) -> String {
        let b64 = Data(engagement).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "mdoc:" + b64
    }

    private static func qrImage(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let context = CIContext()
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
