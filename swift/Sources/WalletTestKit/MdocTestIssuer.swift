import CborCose
import Crypto
import Foundation
import WalletAPI

/// Builds a signed mdoc `IssuerSigned` (ISO 18013-5) for tests — the wallet only ever consumes
/// these, so issuing lives in the test kit. Produces raw `IssuerSigned` CBOR bytes.
public enum MdocTestIssuer {

    private static let tagEncodedCbor: UInt64 = 24
    private static let tagTdate: UInt64 = 0

    public static func issue(
        area: any SecureArea,
        issuerKey: KeyInfo,
        deviceKey: EcPublicKey,
        docType: String,
        namespace: String,
        elements: [(String, Cbor)],
        x5chain: [[UInt8]],
        signed: Date,
        validFrom: Date,
        validUntil: Date,
        digestAlgorithm: String = "SHA-256",
        /// namespace -> authorized device-signed element ids, emitted as MSO `keyAuthorizations.dataElements`.
        authorizedElements: [String: [String]]? = nil
    ) async throws -> [UInt8] {
        var itemEntries: [Cbor] = []
        var digests: [(Cbor, Cbor)] = []
        for (index, element) in elements.enumerated() {
            let digestId = Int64(index)
            let itemMap = Cbor.map([
                (.text("digestID"), .int(digestId)),
                (.text("random"), .bytes((0..<16).map { UInt8((index + $0) & 0xff) })),
                (.text("elementIdentifier"), .text(element.0)),
                (.text("elementValue"), element.1),
            ])
            let tagged = Cbor.tagged(tagEncodedCbor, .bytes(try CborEncoder.encode(itemMap)))
            itemEntries.append(tagged)
            digests.append((.int(digestId), .bytes(digest(digestAlgorithm, try CborEncoder.encode(tagged)))))
        }

        let mso = Cbor.map([
            (.text("version"), .text("1.0")),
            (.text("digestAlgorithm"), .text(digestAlgorithm)),
            (.text("valueDigests"), .map([(.text(namespace), .map(digests))])),
            (.text("deviceKeyInfo"), .map({
                var dki: [(Cbor, Cbor)] = [(.text("deviceKey"), CoseKey.encode(deviceKey))]
                if let auth = authorizedElements {
                    let dataElements = Cbor.map(auth.map { (Cbor.text($0.key), Cbor.array($0.value.map { .text($0) })) })
                    dki.append((.text("keyAuthorizations"), .map([(.text("dataElements"), dataElements)])))
                }
                return dki
            }())),
            (.text("docType"), .text(docType)),
            (.text("validityInfo"), .map([
                (.text("signed"), tdate(signed)),
                (.text("validFrom"), tdate(validFrom)),
                (.text("validUntil"), tdate(validUntil)),
            ])),
        ])
        let msoBytes = try CborEncoder.encode(.tagged(tagEncodedCbor, .bytes(try CborEncoder.encode(mso))))

        let unprotected = CoseHeaders([(.int(33), .array(x5chain.map { .bytes($0) }))])
        let issuerAuth = try await CoseSign1.sign(
            protected: CoseHeaders.of(algorithm: SigningAlgorithm.es256.coseAlgorithm),
            unprotected: unprotected,
            payload: msoBytes,
            signer: SecureAreaCoseSigner(area: area, key: issuerKey.handle, algorithm: .es256)
        )

        let issuerSigned = Cbor.map([
            (.text("nameSpaces"), .map([(.text(namespace), .array(itemEntries))])),
            (.text("issuerAuth"), issuerAuth.toCbor()),
        ])
        return try CborEncoder.encode(issuerSigned)
    }

    private static func tdate(_ date: Date) -> Cbor { .tagged(tagTdate, .text(isoFormatter.string(from: date))) }

    private static func digest(_ algorithm: String, _ bytes: [UInt8]) -> [UInt8] {
        switch algorithm.uppercased() {
        case "SHA-384": return [UInt8](SHA384.hash(data: Data(bytes)))
        case "SHA-512": return [UInt8](SHA512.hash(data: Data(bytes)))
        case "SHA-1": return [UInt8](Insecure.SHA1.hash(data: Data(bytes)))
        default: return [UInt8](SHA256.hash(data: Data(bytes)))
        }
    }

    public static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
