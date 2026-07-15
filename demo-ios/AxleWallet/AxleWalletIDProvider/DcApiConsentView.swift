import AppleDcApi
import IdentityDocumentServices
import IdentityDocumentServicesUI
import Security
import SwiftUI

/// The consent screen the OS presents inside the provider extension for an `org-iso-mdoc` DC API request. Apple's
/// flow is two-phase: pre-consent we only have the OS-parsed, typed `context.request` (what to show the user);
/// the raw `DeviceRequest` bytes we actually sign arrive later inside `sendResponse`. So this view builds its list
/// from `context.request`, shows the requesting site + reader certificate identity, and on "Share" produces the
/// signed, encrypted response via `DcApiResponder` (which auto-discloses `requested ∩ held`).
struct DcApiConsentView: View {
    let context: ISO18013MobileDocumentRequestContext
    private let documents: [RequestedDoc]

    @State private var phase: Phase = .review
    private enum Phase: Equatable { case review, sharing, failed(String) }

    init(context: ISO18013MobileDocumentRequestContext) {
        self.context = context
        self.documents = Self.parse(context.request)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    requester
                    ForEach(documents) { docCard($0) }
                    if documents.isEmpty {
                        Text("This request did not ask for any documents.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if case let .failed(message) = phase {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle("Identity request")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var requester: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(readerName ?? originHost ?? "A website")
                .font(.title3.weight(.semibold))
            Text("is requesting the following from Axle Wallet.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let originHost, readerName != nil {
                Label(originHost, systemImage: "globe").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func docCard(_ doc: RequestedDoc) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(docTitle(doc.docType)).font(.headline)
            ForEach(doc.claims) { claim in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).font(.footnote)
                    Text(humanize(claim.element)).font(.subheadline)
                    Spacer()
                    if claim.retaining {
                        Text("kept").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: share) {
                if phase == .sharing {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Share").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(phase == .sharing || documents.isEmpty)

            Button("Cancel", role: .cancel) { context.cancel() }
                .disabled(phase == .sharing)
        }
        .padding(16)
        .background(.bar)
    }

    private func share() {
        phase = .sharing
        // Hoist to locals so the @Sendable response closure captures Sendable values, not the MainActor view.
        let context = self.context
        let wallet = ExtensionWallet.shared
        Task {
            do {
                try await context.sendResponse { rawRequest in
                    let data = try await DcApiResponder.responseData(
                        rawRequestData: rawRequest.requestData,
                        origin: context.requestingWebsiteOrigin,
                        wallet: wallet)
                    return ISO18013MobileDocumentResponse(responseData: data)
                }
                // The platform dismisses the extension on success.
            } catch {
                phase = .failed(String(describing: error))
            }
        }
    }

    // MARK: - Request model (built once from the OS-parsed request)

    private struct RequestedDoc: Identifiable {
        let docType: String
        let claims: [Claim]
        var id: String { docType }
        struct Claim: Identifiable {
            let namespace: String
            let element: String
            let retaining: Bool
            var id: String { "\(namespace).\(element)" }
        }
    }

    private static func parse(_ request: ISO18013MobileDocumentRequest) -> [RequestedDoc] {
        request.presentmentRequests.flatMap { presentment in
            presentment.documentRequestSets.flatMap { $0.requests }.map { req in
                let claims = req.namespaces
                    .flatMap { ns, elements in
                        elements.map { RequestedDoc.Claim(namespace: ns, element: $0.key, retaining: $0.value.isRetaining) }
                    }
                    .sorted { $0.element < $1.element }
                return RequestedDoc(docType: req.documentType, claims: claims)
            }
        }
    }

    private var readerName: String? {
        guard let cert = context.request.requestAuthentications.first?.authenticationCertificateChain.first else { return nil }
        var cn: CFString?
        guard SecCertificateCopyCommonName(cert, &cn) == errSecSuccess, let cn else { return nil }
        return cn as String
    }

    private var originHost: String? {
        context.requestingWebsiteOrigin?.host ?? context.requestingWebsiteOrigin?.absoluteString
    }

    private func docTitle(_ docType: String) -> String {
        switch docType {
        case "org.iso.18013.5.1.mDL": return "Driver's licence"
        case "eu.europa.ec.eudi.pid.1": return "Personal ID (PID)"
        case "eu.europa.ec.av.1": return "Age verification"
        default: return docType
        }
    }

    private func humanize(_ element: String) -> String {
        element.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
