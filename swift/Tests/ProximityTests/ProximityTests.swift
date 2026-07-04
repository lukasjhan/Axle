import CborCose
import Crypto
import Foundation
import MDoc
import WalletAPI
import WalletTestKit
import XCTest
@testable import Proximity

final class ProximityTests: XCTestCase {

    private func hex(_ s: String) -> [UInt8] {
        stride(from: 0, to: s.count, by: 2).map { i in
            let start = s.index(s.startIndex, offsetBy: i)
            return UInt8(s[start...s.index(start, offsetBy: 1)], radix: 16)!
        }
    }

    func testHkdfMatchesRfc5869Vector() {
        // RFC 5869 Appendix A.1 — confirms swift-crypto HKDF matches the Kotlin (JCA) derivation.
        let okm = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(repeating: 0x0b, count: 22)),
            salt: Data(hex("000102030405060708090a0b0c")),
            info: Data(hex("f0f1f2f3f4f5f6f7f8f9")),
            outputByteCount: 42
        ).withUnsafeBytes { [UInt8]($0) }
        XCTAssertEqual(hex("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"), okm)
    }

    private func transcriptBytes(_ eDevice: EphemeralKeyPair, _ eReader: EphemeralKeyPair) throws -> [UInt8] {
        let de = try DeviceEngagement.qr(eDeviceKey: eDevice.publicKey)
        return try ProximitySessionTranscript.encode(try ProximitySessionTranscript.build(deviceEngagement: de, eReaderKey: eReader.publicKey))
    }

    func testSessionKeyAgreementAndRoundTrip() throws {
        let eDevice = EphemeralKeyPair(), eReader = EphemeralKeyPair()
        let transcript = try transcriptBytes(eDevice, eReader)
        let device = try SessionEncryption.forMdoc(ephemeral: eDevice, readerPublicKey: eReader.publicKey, sessionTranscriptBytes: transcript)
        let reader = try SessionEncryption.forReader(ephemeral: eReader, devicePublicKey: eDevice.publicKey, sessionTranscriptBytes: transcript)

        XCTAssertEqual([UInt8]("hello".utf8), try reader.decrypt(try device.encrypt([UInt8]("hello".utf8))))
        XCTAssertEqual([UInt8]("world".utf8), try device.decrypt(try reader.encrypt([UInt8]("world".utf8))))
        XCTAssertEqual([UInt8]("again".utf8), try reader.decrypt(try device.encrypt([UInt8]("again".utf8))))
    }

    func testTamperedMessageRejected() throws {
        let eDevice = EphemeralKeyPair(), eReader = EphemeralKeyPair()
        let transcript = try transcriptBytes(eDevice, eReader)
        let device = try SessionEncryption.forMdoc(ephemeral: eDevice, readerPublicKey: eReader.publicKey, sessionTranscriptBytes: transcript)
        let reader = try SessionEncryption.forReader(ephemeral: eReader, devicePublicKey: eDevice.publicKey, sessionTranscriptBytes: transcript)

        var ct = try device.encrypt([UInt8]("secret".utf8))
        ct[ct.count - 1] = ct[ct.count - 1] &+ 1
        XCTAssertThrowsError(try reader.decrypt(ct))
    }

    func testMismatchedTranscriptFailsToDecrypt() throws {
        let eDevice = EphemeralKeyPair(), eReader = EphemeralKeyPair()
        let device = try SessionEncryption.forMdoc(ephemeral: eDevice, readerPublicKey: eReader.publicKey, sessionTranscriptBytes: try transcriptBytes(eDevice, eReader))
        let reader = try SessionEncryption.forReader(ephemeral: eReader, devicePublicKey: eDevice.publicKey, sessionTranscriptBytes: [UInt8]("other".utf8))
        XCTAssertThrowsError(try reader.decrypt(try device.encrypt([UInt8]("x".utf8))))
    }

    func testDeviceResponseSignedOverProximityTranscript() async throws {
        let docType = "org.iso.18013.5.1.mDL", namespace = "org.iso.18013.5.1"
        let area = SoftwareSecureArea()
        let issuerKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let deviceKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let mdocBytes = try await MdocTestIssuer.issue(
            area: area, issuerKey: issuerKey, deviceKey: deviceKey.publicKey, docType: docType, namespace: namespace,
            elements: [("family_name", .text("Han")), ("given_name", .text("Jongho"))], x5chain: [[0x30, 0x01]],
            signed: MdocTestIssuer.isoFormatter.date(from: "2026-01-01T00:00:00Z")!,
            validFrom: MdocTestIssuer.isoFormatter.date(from: "2026-01-01T00:00:00Z")!,
            validUntil: MdocTestIssuer.isoFormatter.date(from: "2027-01-01T00:00:00Z")!)

        let eDevice = EphemeralKeyPair(), eReader = EphemeralKeyPair()
        let sessionTranscript = try ProximitySessionTranscript.build(deviceEngagement: try DeviceEngagement.qr(eDeviceKey: eDevice.publicKey), eReaderKey: eReader.publicKey)
        let deviceResponse = try await MdocPresenter.deviceResponse(
            issuerSigned: try IssuerSigned.decode(mdocBytes), docType: docType, disclosed: [namespace: ["family_name"]],
            sessionTranscript: sessionTranscript, deviceSigner: SecureAreaCoseSigner(area: area, key: deviceKey.handle, algorithm: .es256))

        func field(_ c: Cbor, _ k: String) -> Cbor { guard case let .map(e) = c else { fatalError() }; return e.first { if case let .text(t) = $0.0 { return t == k }; return false }!.1 }
        guard case let .array(documents) = field(try CborDecoder.decode(deviceResponse), "documents") else { return XCTFail() }
        let document = documents[0]
        let deviceSignature = try CoseSign1.fromCbor(field(field(field(document, "deviceSigned"), "deviceAuth"), "deviceSignature"))
        let deviceNsBytes = Cbor.tagged(24, .bytes(try CborEncoder.encode(.map([]))))
        let deviceAuth = Cbor.array([.text("DeviceAuthentication"), sessionTranscript, .text(docType), deviceNsBytes])
        let deviceAuthBytes = try CborEncoder.encode(.tagged(24, .bytes(try CborEncoder.encode(deviceAuth))))
        XCTAssertTrue(deviceSignature.verify(publicKey: deviceKey.publicKey, detachedPayload: deviceAuthBytes))

        let disclosed = try IssuerSigned.fromCbor(field(document, "issuerSigned")).nameSpaces.first!.1.map { $0.item.elementIdentifier }
        XCTAssertEqual(["family_name"], disclosed)
    }
}
