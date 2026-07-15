import SwiftUI
import Wallet
import WalletAPI

/// OpenID4VCI issuance flow — a 1:1 mirror of android `IssueScreen`, in both behavior and layout:
/// Review → (TxCode) → Issuing → ReviewCredential → Success, or Failed. Brand palette + Manrope + the shared
/// credential cards, matching the android screen. The auth-code grant opens a browser
/// (ASWebAuthenticationSession) and resumes via `completeAuthorization`.
struct IssueView: View {
    let offer: CredentialOffer
    /// "View in wallet" / success path — dismiss and reload the wallet lists.
    let onDone: () -> Void
    /// Cancelled or failed — dismiss without reload (an already-issued credential is deleted first).
    let onCancel: () -> Void

    @State private var step: IssueStep = .review
    @State private var preview: OfferPreview?
    @State private var previewLoading = true
    @State private var txCode = ""
    @State private var issued: Credential?
    @State private var errorMessage: String?
    @State private var confirmCancel = false

    private let wallet = DemoWallet.shared

    enum IssueStep { case review, txCode, issuing, reviewCredential, success, failed }

    private var configId: String { offer.credentialConfigurationIds.first ?? "" }
    private var showsHeader: Bool { step == .review || step == .txCode || step == .reviewCredential }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                FlowTopBar(title: step == .reviewCredential ? "Review credential" : "Add document") { back() }
                Spacer().frame(height: 20)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WalletTheme.screen.ignoresSafeArea())
        .task { await loadPreview() }
        .alert(cancelTitle, isPresented: $confirmCancel) {
            Button(step == .reviewCredential ? "Discard" : "Cancel adding", role: .destructive) {
                Task { await finishCancel() }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text(cancelBody)
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .review: reviewStep
        case .txCode: txCodeStep
        case .issuing: FlowLoading(title: "Issuing…", subtitle: "Contacting the issuer and verifying the credential.")
        case .reviewCredential: reviewCredentialStep
        case .success: FlowResult(kind: .success, title: "Document added", subtitle: "Saved securely on this device.", buttonTitle: "View in wallet", onButton: onDone)
        case .failed: FlowResult(kind: .failure, title: "Couldn't add document", subtitle: errorMessage ?? "The issuance failed.", buttonTitle: "Close", onButton: onCancel)
        }
    }

    private var reviewStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    newDocumentCard
                    SectionLabel("Issuer")
                    issuerCard
                    if let preview, !preview.issuerRegistered, !previewLoading {
                        FlowNote("This issuer isn't on the EU trusted list. You can still add the document.")
                    }
                    if let preview, preview.credentials.count > 1 {
                        SectionLabel("You'll receive")
                        WalletCard(padding: .flush) {
                            ForEach(preview.credentials, id: \.configurationId) { c in
                                WalletInfoRow(label: c.displayName ?? prettyConfig(c.configurationId), value: formatLabel(c.format))
                            }
                        }
                    }
                    if offer.requiresTxCode {
                        FlowNote("This issuer will ask for a transaction code.")
                    }
                }
            }
            FlowFooter(
                primaryTitle: "Continue",
                onPrimary: { if offer.requiresTxCode { step = .txCode } else { Task { await runIssuance(code: nil) } } },
                secondaryTitle: "Cancel",
                onSecondary: { confirmCancel = true }
            )
        }
    }

    private var newDocumentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("NEW DOCUMENT").font(WalletFont.labelSmall).tracking(0.6).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Pill(text: primaryFormatLabel, bg: .white.opacity(0.12), fg: .white)
            }
            Spacer().frame(height: 22)
            Text(primaryTitle).font(WalletFont.titleMedium).foregroundStyle(.white)
            Text(hostOf(offer.credentialIssuer)).font(WalletFont.bodySmall).foregroundStyle(.white.opacity(0.75)).padding(.top, 3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: DocGradients.pid, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private var issuerCard: some View {
        WalletCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview?.issuerDisplayName ?? hostOf(offer.credentialIssuer)).font(WalletFont.titleSmall).foregroundStyle(WalletTheme.ink)
                    Text(hostOf(offer.credentialIssuer)).font(WalletFont.bodySmall).foregroundStyle(WalletTheme.inkMuted)
                }
                Spacer()
                if previewLoading {
                    ProgressView().tint(WalletTheme.brand).controlSize(.small)
                } else {
                    TrustPill(trusted: preview?.issuerRegistered == true, trustedText: "Registered", untrustedText: "Unverified")
                }
            }
        }
    }

    private var txCodeStep: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter the transaction code").font(WalletFont.titleSmall).foregroundStyle(WalletTheme.ink)
                Text("The issuer sent you a code to authorise this credential.").font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.inkMuted)
                if let desc = offer.txCode?.description { FlowNote(desc) }
                TextField("Transaction code", text: $txCode)
                    .font(WalletFont.bodyLarge)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(WalletTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WalletTheme.cardBorderStrong, lineWidth: 1))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(offer.txCode?.inputMode == "text" ? .default : .numberPad)
            }
            Spacer()
            PrimaryButton(title: "Issue", enabled: !txCode.trimmingCharacters(in: .whitespaces).isEmpty) {
                Task { await runIssuance(code: txCode) }
            }
        }
    }

    @ViewBuilder private var reviewCredentialStep: some View {
        if let issued {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Review the credential you received before saving it to your wallet.")
                            .font(WalletFont.bodyMedium).foregroundStyle(WalletTheme.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CredentialGradientCard(cred: issued)
                        SectionLabel("Trust")
                        CredentialTrustCard(cred: issued)
                        CredentialClaimSections(cred: issued, reveal: true)
                    }
                }
                FlowFooter(primaryTitle: "Save to wallet", onPrimary: { step = .success },
                           secondaryTitle: "Discard", onSecondary: { confirmCancel = true })
            }
        } else {
            FlowLoading(title: "Finishing…")
        }
    }

    // MARK: - Behavior

    private func loadPreview() async {
        previewLoading = true
        preview = try? await wallet.issuance.previewOffer(offer)
        previewLoading = false
    }

    /// Drives the SDK issuance session to a terminal state, mirroring android `runIssuance`'s collector.
    private func runIssuance(code: String?) async {
        step = .issuing
        let request = IssuanceRequest.fromOffer(offer, configurationId: configId, txCode: code)
        let session = wallet.issuance.start(request)
        for await state in session.states {
            switch state {
            case .txCodeRequired:
                if let code { session.submitTxCode(code) }
            case let .authorizationRequired(url):
                await authorize(url: url, session: session)
            case .completed:
                issued = try? await wallet.credentials.list().max { $0.createdAt < $1.createdAt }
                step = .reviewCredential
                return
            case .deferred:
                issued = nil
                step = .success
                return
            case let .failed(error):
                errorMessage = error.displayMessage
                step = .failed
                return
            case .preparing, .processing:
                break
            }
        }
    }

    private func authorize(url: String, session: IssuanceSession) async {
        guard let authURL = URL(string: url) else {
            session.cancel(); errorMessage = "Invalid authorization URL."; step = .failed; return
        }
        let coordinator = WebAuthCoordinator()
        do {
            let redirect = try await coordinator.authorize(url: authURL, callbackScheme: "eu.europa.ec.euidi")
            session.completeAuthorization(redirect)
        } catch {
            session.cancel()
            errorMessage = "Authorization was cancelled."
            step = .failed
        }
    }

    private func back() {
        switch step {
        case .txCode: step = .review
        case .review, .reviewCredential: confirmCancel = true
        case .success: onDone()
        case .failed: onCancel()
        case .issuing: break
        }
    }

    /// Confirmed discard/cancel: delete an already-issued credential (ReviewCredential) then dismiss.
    private func finishCancel() async {
        if step == .reviewCredential, let issued {
            try? await wallet.credentials.delete(issued.id)
        }
        onCancel()
    }

    private var cancelTitle: String {
        step == .reviewCredential ? "Discard this credential?" : "Cancel adding this document?"
    }
    private var cancelBody: String {
        step == .reviewCredential ? "It won't be saved to your wallet." : "You'll need to start over to add it."
    }

    private var primaryFormatLabel: String { formatLabel(preview?.credentials.first?.format ?? "") }
    private var primaryTitle: String {
        preview?.credentials.first?.displayName ?? prettyConfig(configId)
    }
}

// MARK: - Helpers (shared across flow screens)

func formatString(_ format: CredentialFormat) -> String {
    switch format {
    case .msoMdoc: return "mso_mdoc"
    case .sdJwtVc: return "sd-jwt-vc"
    }
}

func docTypeOrVct(_ format: CredentialFormat) -> String {
    switch format {
    case let .msoMdoc(docType): return docType
    case let .sdJwtVc(vct): return vct
    }
}

func formatLabel(_ format: String) -> String {
    let f = format.lowercased()
    if f.contains("sd-jwt") || f.contains("sd_jwt") || f.contains("dc+sd") { return "SD-JWT VC" }
    if f.contains("mdoc") || f.contains("mso") { return "mdoc" }
    return format.isEmpty ? "Credential" : format
}

func prettyConfig(_ id: String) -> String {
    let last = id.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? id
    let spaced = last.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ")
    let trimmed = spaced.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.first else { return "Credential" }
    return first.uppercased() + trimmed.dropFirst()
}

func hostOf(_ url: String) -> String {
    URL(string: url)?.host ?? url
}

extension IssuanceError {
    var displayMessage: String {
        switch self {
        case let .invalidOffer(m): return m
        case let .authorizationFailed(_, m): return m
        case let .credentialRequestFailed(m): return m
        case let .unexpected(m): return m
        }
    }
}
