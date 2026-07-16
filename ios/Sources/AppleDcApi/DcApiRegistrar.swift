import Foundation
import IdentityDocumentServices
import Wallet
import WalletAPI

/// Registers the wallet's mdoc credentials with the OS so Safari (and any WebKit browser) can offer Axle Wallet as
/// a candidate for an `org-iso-mdoc` Digital Credentials API request. The iOS mirror of android `DcApiRegistrar` —
/// but iOS needs **no WASM matcher**: the OS owns matching and the credential picker, so this is just registration.
///
/// Only mdoc (CBOR) credentials are registrable — SD-JWT VC cannot be presented over the iOS DC API. Each doctype
/// must also appear in the app's `identity-document-services.document-provider.mobile-document-types` entitlement,
/// or the OS rejects the registration.
@available(iOS 26.0, *)
public enum DcApiRegistrar {
    /// Re-syncs the OS registry to the wallet's current mdoc credentials: registers each stored mdoc and prunes any
    /// registration whose credential is gone. Idempotent and cheap — call on wallet ready and on every credential
    /// change (mirrors android's re-register-on-change). Returns the number of documents registered.
    @discardableResult
    public static func sync(wallet: Wallet, log: ((String) -> Void)? = nil) async -> Int {
        let store = IdentityDocumentProviderRegistrationStore()
        let status = (try? await store.status).map { "\($0)" } ?? "unavailable"
        guard status != "notSupported" else {
            log?("DC API: registry not supported on this device — skipping")
            return 0
        }
        do {
            let wanted = try await wallet.credentials.list().reduce(into: [String: MobileDocumentRegistration]()) {
                if let reg = registration(for: $1) { $0[reg.documentIdentifier] = reg }
            }
            let docTypes = Set(wanted.values.map(\.mobileDocumentType)).sorted().joined(separator: ", ")
            log?("DC API: status=\(status); \(wanted.count) mdoc doc(s) to register [\(docTypes)]")
            // Prune registrations whose credential no longer exists.
            if let existing = try? await store.registrations {
                for reg in existing where wanted[reg.documentIdentifier] == nil {
                    try? await store.removeRegistration(forDocumentIdentifier: reg.documentIdentifier)
                }
            }
            // Register each independently — a doctype absent from the app's `mobile-document-types` entitlement
            // throws `notAuthorized` for THAT type only; don't let it block the others, and name it in the log.
            var registered = 0
            for reg in wanted.values {
                do { try await store.addRegistration(reg); registered += 1 }
                catch { log?("DC API: register '\(reg.mobileDocumentType)' failed: \(error)") }
            }
            log?("DC API: registered \(registered)/\(wanted.count) document(s)")
            return registered
        } catch {
            log?("DC API registration failed: \(error)")
            return 0
        }
    }

    /// Removes every registration for this wallet (used on wallet reset). Best-effort.
    public static func clear(log: ((String) -> Void)? = nil) async {
        let store = IdentityDocumentProviderRegistrationStore()
        guard let existing = try? await store.registrations else { return }
        for reg in existing {
            try? await store.removeRegistration(forDocumentIdentifier: reg.documentIdentifier)
        }
        log?("DC API: cleared registrations")
    }

    private static func registration(for c: Credential) -> MobileDocumentRegistration? {
        guard case let .msoMdoc(docType) = c.format, case let .issued(_, validity, _) = c.lifecycle else { return nil }
        return MobileDocumentRegistration(
            mobileDocumentType: docType,
            supportedAuthorityKeyIdentifiers: [], // no issuer filtering — the consent screen surfaces the reader instead
            documentIdentifier: c.id.value,
            invalidationDate: validity?.validUntil)
    }
}
