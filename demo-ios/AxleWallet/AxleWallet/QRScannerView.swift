import SwiftUI
import Vision
import VisionKit

/// VisionKit QR scanner — the iOS counterpart of the android demo's ZXing scan launcher. QR-only,
/// fires `onScan` once with the payload string.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var handled = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !handled else { return }
            for case let .barcode(barcode) in addedItems {
                if let value = barcode.payloadStringValue {
                    handled = true
                    onScan(value)
                    return
                }
            }
        }
    }
}

/// Presents the scanner full-screen with a Cancel button and a prompt matching the android copy.
struct ScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if QRScannerView.isSupported {
                    QRScannerView { value in
                        onScan(value)
                        dismiss()
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        Text("Scan an issuer offer or a verifier request")
                            .font(.callout)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 40)
                    }
                } else {
                    ContentUnavailableView(
                        "Camera unavailable",
                        systemImage: "camera.fill",
                        description: Text("QR scanning needs a device camera.")
                    )
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
