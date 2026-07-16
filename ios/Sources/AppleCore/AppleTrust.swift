import Foundation
import TrustList
import WalletAPI

/// The wallet's trust anchors (DER), for `TrustConfig(issuerAnchorsDer:readerAnchorsDer:registrarAnchorsDer:)`.
public struct AppleTrustAnchors: Sendable {
    public let issuer: [[UInt8]]
    public let reader: [[UInt8]]
    public let registrar: [[UInt8]]

    public var isEmpty: Bool { issuer.isEmpty && reader.isEmpty && registrar.isEmpty }
    public var summary: String { "issuer=\(issuer.count) reader=\(reader.count) registrar=\(registrar.count)" }
}

/// Pulls CA anchors from the sandbox JAdES **trusted lists** (verified against the pinned Scheme Operator
/// cert), so the wallet can verify our issuer (credential DSC / signed metadata), verifier (WRPAC + WRPRC),
/// and registrar. The iOS counterpart of android `DemoWallet.resolveTrust`: a disk cache with a TTL, falling
/// back to a stale cache on a fetch failure so an outage doesn't strip the wallet of trust.
public enum AppleTrust {
    public static func resolve(
        http: any HttpTransport,
        base: String = "https://trusted-list.vercel.app/tl",
        cacheDir: URL,
        ttl: TimeInterval = 24 * 60 * 60,
        log: (@Sendable (String) -> Void)? = nil
    ) async -> AppleTrustAnchors {
        if let (cached, age) = loadCache(cacheDir), age < ttl {
            log?("trusted-list: using cached anchors (age \(Int(age))s) — \(cached.summary)")
            return cached
        }
        let fetched = await fetch(http: http, base: base, log: log)
        if !fetched.issuer.isEmpty || !fetched.registrar.isEmpty {
            saveCache(cacheDir, fetched)
            log?("trusted-list: fetched anchors — \(fetched.summary)")
            return fetched
        }
        if let (cached, _) = loadCache(cacheDir) {
            log?("trusted-list: fetch failed, using stale cache — \(cached.summary)")
            return cached
        }
        log?("trusted-list: no anchors (offline, no cache) — trust unavailable")
        return AppleTrustAnchors(issuer: [], reader: [], registrar: [])
    }

    private static func fetch(http: any HttpTransport, base: String, log: (@Sendable (String) -> Void)?) async -> AppleTrustAnchors {
        let client = TrustedListClient(http: http)
        guard let pem = try? await fetchText(http, "\(base)/scheme-operator.pem"), let soDer = pemToDer(pem) else {
            log?("trusted-list: scheme-operator fetch failed")
            return AppleTrustAnchors(issuer: [], reader: [], registrar: [])
        }
        func anchors(_ slug: String) async -> [[UInt8]] {
            do {
                return try await client.fetchCACerts(url: "\(base)/\(slug).jades.json", schemeOperatorAnchorDer: soDer)
            } catch {
                log?("trusted-list: '\(slug)' fetch failed: \(error)")
                return []
            }
        }
        // Issued credentials chain to the PID + attestation issuer CAs; the verifier's WRPAC (and its
        // WRPRC / status list / TS5 registry) chains to the registrar CA — which holders also trust as a reader anchor.
        let issuer = await anchors("pid-issuers") + anchors("attestation-issuers")
        let registrar = await anchors("registrar")
        return AppleTrustAnchors(issuer: issuer, reader: registrar, registrar: registrar)
    }

    // MARK: - HTTP + PEM

    private static func fetchText(_ http: any HttpTransport, _ url: String) async throws -> String {
        let response = try await http.execute(HttpRequest(method: .get, url: url, headers: [("Accept", "*/*")]))
        guard (200..<300).contains(response.status) else {
            throw NSError(domain: "AppleTrust", code: response.status, userInfo: [NSLocalizedDescriptionKey: "HTTP \(response.status) for \(url)"])
        }
        return String(decoding: response.body, as: UTF8.self)
    }

    private static func pemToDer(_ pem: String) -> [UInt8]? {
        let b64 = pem
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        return Data(base64Encoded: b64).map { [UInt8]($0) }
    }

    // MARK: - Disk cache (<cacheDir>/{fetchedAt, issuer/*.der, registrar/*.der})

    private static func loadCache(_ cacheDir: URL) -> (AppleTrustAnchors, TimeInterval)? {
        let stampURL = cacheDir.appendingPathComponent("fetchedAt")
        guard let stampText = try? String(contentsOf: stampURL, encoding: .utf8),
              let stamp = TimeInterval(stampText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let issuer = ders(cacheDir.appendingPathComponent("issuer"))
        let registrar = ders(cacheDir.appendingPathComponent("registrar"))
        guard !issuer.isEmpty || !registrar.isEmpty else { return nil }
        let anchors = AppleTrustAnchors(issuer: issuer, reader: registrar, registrar: registrar)
        return (anchors, Date().timeIntervalSince1970 - stamp)
    }

    private static func ders(_ dir: URL) -> [[UInt8]] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "der" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? Data(contentsOf: $0) }.map { [UInt8]($0) }
    }

    private static func saveCache(_ cacheDir: URL, _ anchors: AppleTrustAnchors) {
        let fm = FileManager.default
        func write(_ sub: String, _ ders: [[UInt8]]) {
            let dir = cacheDir.appendingPathComponent(sub)
            try? fm.removeItem(at: dir)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for (i, der) in ders.enumerated() {
                try? Data(der).write(to: dir.appendingPathComponent(String(format: "%03d.der", i)))
            }
        }
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        write("issuer", anchors.issuer)
        write("registrar", anchors.registrar) // == reader
        try? String(Date().timeIntervalSince1970).data(using: .utf8)?.write(to: cacheDir.appendingPathComponent("fetchedAt"))
    }
}
