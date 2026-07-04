import CborCose
import Foundation
import WalletAPI

/// Builds an mdoc `DeviceResponse` (ISO 18013-5 §8.3.2.1.2.2) for presentation: keeps only the
/// disclosed issuer-signed items and produces `DeviceSigned` — a `deviceSignature` COSE_Sign1
/// over the `DeviceAuthentication` structure (detached payload) bound to the `sessionTranscript`.
public enum MdocPresenter {

    private static let tagEncodedCbor: UInt64 = 24

    public static func deviceResponse(
        issuerSigned: IssuerSigned,
        docType: String,
        disclosed: [String: [String]], // namespace -> element identifiers to disclose
        sessionTranscript: Cbor,
        deviceSigner: any CoseSigner,
        deviceSignAlgorithm: SigningAlgorithm = .es256
    ) async throws -> [UInt8] {
        // Keep only the disclosed items, re-emitting their exact IssuerSignedItemBytes (#6.24).
        var filteredNs: [(Cbor, Cbor)] = []
        for (ns, items) in issuerSigned.nameSpaces {
            guard let ids = disclosed[ns] else { continue }
            let kept = try items.filter { ids.contains($0.item.elementIdentifier) }.map { try CborDecoder.decode($0.itemBytes) }
            if !kept.isEmpty { filteredNs.append((.text(ns), .array(kept))) }
        }
        let issuerSignedCbor = Cbor.map([
            (.text("nameSpaces"), .map(filteredNs)),
            (.text("issuerAuth"), issuerSigned.issuerAuth.toCbor(tagged: false)),
        ])

        // DeviceNameSpaces is empty for a basic presentation.
        let deviceNameSpacesBytes = Cbor.tagged(tagEncodedCbor, .bytes(try CborEncoder.encode(.map([]))))

        let deviceAuth = Cbor.array([.text("DeviceAuthentication"), sessionTranscript, .text(docType), deviceNameSpacesBytes])
        let deviceAuthBytes = try CborEncoder.encode(.tagged(tagEncodedCbor, .bytes(try CborEncoder.encode(deviceAuth))))

        let deviceSignature = try await CoseSign1.sign(
            protected: CoseHeaders.of(algorithm: deviceSignAlgorithm.coseAlgorithm),
            payload: nil,
            detachedPayload: deviceAuthBytes,
            signer: deviceSigner
        )

        let deviceSigned = Cbor.map([
            (.text("nameSpaces"), deviceNameSpacesBytes),
            (.text("deviceAuth"), .map([(.text("deviceSignature"), deviceSignature.toCbor(tagged: false))])),
        ])

        let document = Cbor.map([
            (.text("docType"), .text(docType)),
            (.text("issuerSigned"), issuerSignedCbor),
            (.text("deviceSigned"), deviceSigned),
        ])
        let deviceResponse = Cbor.map([
            (.text("version"), .text("1.0")),
            (.text("documents"), .array([document])),
            (.text("status"), .int(0)),
        ])
        return try CborEncoder.encode(deviceResponse)
    }
}
