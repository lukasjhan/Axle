import AppleCore
import Foundation
import Security

/// Shares the wallet's reader (verifier) trust anchors between the app and the DC API provider extension through
/// the App Group container, and validates a reader's authentication certificate chain against them — so the
/// extension's consent screen can mark a requester *verified* (ISO 18013-5 §9.1.4 reader authentication, chained
/// to a configured reader anchor).
///
/// The extension is a separate, offline process: it cannot fetch the trusted lists itself, so the app writes the
/// resolved reader anchors here on boot and the extension reads them at consent time.
public enum DcApiReaderTrust {
    private static var anchorsFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppleSharedGroups.appGroup)?
            .appendingPathComponent("dcapi-reader-anchors.json")
    }

    /// Persist the reader trust anchors (DER-encoded X.509) to the shared container. Called by the app after it
    /// resolves its trusted lists.
    public static func cache(readerAnchorsDer: [[UInt8]]) {
        guard let anchorsFileURL else { return }
        let base64 = readerAnchorsDer.map { Data($0).base64EncodedString() }
        guard let data = try? JSONSerialization.data(withJSONObject: base64) else { return }
        try? data.write(to: anchorsFileURL, options: .atomic)
    }

    /// The cached reader anchors as `SecCertificate`s (empty until the app has run once with anchors resolved).
    public static func cachedAnchors() -> [SecCertificate] {
        guard let anchorsFileURL, let data = try? Data(contentsOf: anchorsFileURL),
              let base64 = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { return [] }
        return base64
            .compactMap { Data(base64Encoded: $0) }
            .compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
    }

    public struct Reader {
        public let verified: Bool
        public let commonName: String?
    }

    /// Validate a reader's authentication certificate chain (leaf-first, from `context.request`) against the
    /// cached reader anchors. `verified` is true only when the chain builds to a cached anchor; the common name is
    /// always returned (for display) even when unverified or no anchors are cached.
    public static func evaluate(chain: [SecCertificate]) -> Reader {
        let commonName = chain.first.flatMap(Self.commonName)
        let anchors = cachedAnchors()
        guard !chain.isEmpty, !anchors.isEmpty else { return Reader(verified: false, commonName: commonName) }

        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(chain as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust else {
            return Reader(verified: false, commonName: commonName)
        }
        SecTrustSetAnchorCertificates(trust, anchors as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true) // trust ONLY our reader anchors, not the system roots
        let verified = SecTrustEvaluateWithError(trust, nil)
        return Reader(verified: verified, commonName: commonName)
    }

    private static func commonName(_ cert: SecCertificate) -> String? {
        var cn: CFString?
        return SecCertificateCopyCommonName(cert, &cn) == errSecSuccess ? cn as String? : nil
    }
}
