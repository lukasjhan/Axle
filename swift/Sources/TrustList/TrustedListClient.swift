import CborCose
import Foundation
import SdJwt
import Trust
import WalletAPI

public struct TrustListError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

/// Fetches an ETSI TS 119 602 Trusted List (JAdES-signed, as published by the Scheme Operator) from a URL,
/// verifies the Scheme Operator's signature against a pinned anchor, and returns the listed service CA
/// certificates as DER — ready to feed into `TrustConfig` (issuer / reader / registrar anchors).
///
/// This is a deliberately standalone module: the core trust validators stay DER-based and never depend on
/// it, so a host that does not use a Trusted List can keep supplying DER directly. The list carries a JAdES
/// B-B signature (`crit` present), so the signature is verified directly (as `WRPRCVerifier` does), not via
/// `Jws.verify`.
public struct TrustedListClient {
    private let http: any HttpTransport

    public init(http: any HttpTransport) {
        self.http = http
    }

    /// - Parameters:
    ///   - url: the JAdES-signed list, e.g. `https://…/tl/registrar.jades.json`.
    ///   - schemeOperatorAnchorDer: the pinned Scheme Operator signing certificate (DER); the list signature
    ///     is verified against its key.
    /// - Returns: the DER of each listed service certificate (the CA anchors).
    public func fetchCACerts(url: String, schemeOperatorAnchorDer: [UInt8]) async throws -> [[UInt8]] {
        let resp = try await http.execute(
            HttpRequest(method: .get, url: url, headers: [("Accept", "application/json")], body: nil)
        )
        guard (200...299).contains(resp.status) else {
            throw TrustListError("trusted list fetch failed: HTTP \(resp.status)")
        }
        return try verifyAndExtract(Array(resp.body), schemeOperatorAnchorDer: schemeOperatorAnchorDer)
    }

    /// Verifies an already-fetched flattened-JWS list body and extracts the CA DERs (exposed for offline use/tests).
    public func verifyAndExtract(_ body: [UInt8], schemeOperatorAnchorDer: [UInt8]) throws -> [[UInt8]] {
        let envelope = try JsonValue.parse(String(decoding: body, as: UTF8.self))
        guard case let .str(protectedB64)? = envelope["protected"],
              case let .str(payloadB64)? = envelope["payload"],
              case let .str(signatureB64)? = envelope["signature"]
        else {
            throw TrustListError("trusted list is not a flattened JWS { protected, payload, signature }")
        }

        // --- Scheme Operator signature (JAdES B-B) — verify directly against the pinned anchor's key. ---
        let header = try JsonValue.parse(try Base64Url.decodeToString(protectedB64))
        guard case let .str(alg)? = header["alg"], alg == "ES256" else {
            throw TrustListError("trusted list alg must be ES256")
        }
        let key = try X509Support.ecPublicKey(try X509Support.parse(schemeOperatorAnchorDer))
        let signingInput = Array("\(protectedB64).\(payloadB64)".utf8)
        let signature = try Base64Url.decode(signatureB64)
        guard Ecdsa.verify(
            key: key,
            algorithm: SigningAlgorithm.es256.coseAlgorithm,
            data: signingInput,
            rawSignature: signature
        ) else {
            throw TrustListError("trusted list signature does not verify against the Scheme Operator anchor")
        }

        // --- Extract the listed service certificates (base64 DER, per TS 119 602). ---
        let payload = try JsonValue.parse(try Base64Url.decodeToString(payloadB64))
        var cas: [[UInt8]] = []
        if case let .arr(entities)? = payload["trustedEntitiesList"] {
            for entity in entities {
                guard case let .arr(services)? = entity["trustedEntityServices"] else { continue }
                for service in services {
                    if case let .str(certB64)? = service["serviceDigitalIdentity"]?["x509Certificate"] {
                        cas.append(try base64Decode(certB64))
                    }
                }
            }
        }
        guard !cas.isEmpty else { throw TrustListError("trusted list has no service certificates") }
        return cas
    }

    /// Standard base64 (the Trusted List encodes certificates as base64 DER, not base64url).
    private func base64Decode(_ text: String) throws -> [UInt8] {
        guard let data = Data(base64Encoded: text) else { throw TrustListError("invalid base64 certificate") }
        return [UInt8](data)
    }
}
