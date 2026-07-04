import CborCose
import Foundation
import MDoc
import SdJwt
import WalletAPI
import WalletTestKit
import XCTest
@testable import OpenID4VP

final class MdocPresentationTests: XCTestCase {

    private let docType = "org.iso.18013.5.1.mDL"
    private let namespace = "org.iso.18013.5.1"

    private var ctx: PresentationContext {
        PresentationContext(
            disclosedPaths: [["org.iso.18013.5.1", "family_name"], ["org.iso.18013.5.1", "given_name"]],
            clientId: "x509_hash:abc", nonce: "nonce-123", responseUri: "https://verifier.example/response",
            issuedAt: 1_700_000_000, transactionData: nil, verifierJwkThumbprint: nil)
    }

    private func field(_ c: Cbor, _ key: String) -> Cbor? {
        guard case let .map(entries) = c else { return nil }
        return entries.first { if case let .text(t) = $0.0 { return t == key }; return false }?.1
    }

    func testPresentsDeviceResponseWithSelectiveDisclosureAndDeviceSignature() async throws {
        let area = SoftwareSecureArea()
        let issuerKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let deviceKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let bytes = try await MdocTestIssuer.issue(
            area: area, issuerKey: issuerKey, deviceKey: deviceKey.publicKey,
            docType: docType, namespace: namespace,
            elements: [("family_name", .text("Han")), ("given_name", .text("Jongho")), ("age_over_18", .bool(true))],
            x5chain: [[0x30, 0x01]],
            signed: MdocTestIssuer.isoFormatter.date(from: "2026-01-01T00:00:00Z")!,
            validFrom: MdocTestIssuer.isoFormatter.date(from: "2026-01-01T00:00:00Z")!,
            validUntil: MdocTestIssuer.isoFormatter.date(from: "2027-01-01T00:00:00Z")!)
        let held = try HeldMdoc(credentialId: "mdl-1", issuerSigned: try IssuerSigned.decode(bytes),
                                deviceSigner: SecureAreaCoseSigner(area: area, key: deviceKey.handle, algorithm: .es256))

        let deviceResponseB64 = try await held.present(ctx)
        let deviceResponse = try CborDecoder.decode(Base64Url.decode(deviceResponseB64))

        XCTAssertEqual(.text("1.0"), field(deviceResponse, "version"))
        guard case let .array(documents)? = field(deviceResponse, "documents") else { return XCTFail("no documents") }
        let document = documents[0]
        XCTAssertEqual(.text(docType), field(document, "docType"))

        // selective disclosure: only family_name + given_name, age_over_18 withheld
        let presentedIssuerSigned = try IssuerSigned.fromCbor(field(document, "issuerSigned")!)
        let disclosedIds = Set(presentedIssuerSigned.nameSpaces.first!.1.map { $0.item.elementIdentifier })
        XCTAssertEqual(["family_name", "given_name"], disclosedIds)

        // device signature verifies over the reconstructed DeviceAuthenticationBytes
        let deviceSigned = field(document, "deviceSigned")!
        let deviceSignature = try CoseSign1.fromCbor(field(field(deviceSigned, "deviceAuth")!, "deviceSignature")!)
        let deviceAuthBytes = try reconstructDeviceAuthBytes()
        XCTAssertTrue(deviceSignature.verify(publicKey: deviceKey.publicKey, detachedPayload: deviceAuthBytes))
    }

    private func reconstructDeviceAuthBytes() throws -> [UInt8] {
        let st = try Oid4vpSessionTranscript.build(clientId: ctx.clientId, responseUri: ctx.responseUri, nonce: ctx.nonce, verifierJwkThumbprint: ctx.verifierJwkThumbprint)
        let deviceNameSpacesBytes = Cbor.tagged(24, .bytes(try CborEncoder.encode(.map([]))))
        let deviceAuth = Cbor.array([.text("DeviceAuthentication"), st, .text(docType), deviceNameSpacesBytes])
        return try CborEncoder.encode(.tagged(24, .bytes(try CborEncoder.encode(deviceAuth))))
    }
}
