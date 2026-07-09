import CborCose
import Foundation
import MDoc
import SdJwt
import WalletAPI
import WalletTestKit
import XCTest
@testable import OpenID4VP

/// OpenID4VP mdoc transaction_data (ISO 18013-7 B.2.1): a host-supplied binder turns a transaction_data entry
/// into a device-signed data element, which the wallet device-signs only after checking the MSO
/// `keyAuthorizations` (§9.1.2.4) authorized it.
final class MdocTransactionDataTests: XCTestCase {

    private let docType = "org.iso.18013.5.1.mDL"
    private let namespace = "org.iso.18013.5.1"

    private func mdoc(_ area: SoftwareSecureArea, _ issuerKey: KeyInfo, _ deviceKey: EcPublicKey,
                      authorized: [String: [String]]?) async throws -> IssuerSigned {
        let bytes = try await MdocTestIssuer.issue(
            area: area, issuerKey: issuerKey, deviceKey: deviceKey, docType: docType, namespace: namespace,
            elements: [("family_name", .text("Han"))], x5chain: [[0x30, 0x01]],
            signed: MdocTestIssuer.isoFormatter.date(from: "2026-01-01T00:00:00Z")!,
            validFrom: MdocTestIssuer.isoFormatter.date(from: "2026-01-01T00:00:00Z")!,
            validUntil: MdocTestIssuer.isoFormatter.date(from: "2027-01-01T00:00:00Z")!,
            authorizedElements: authorized)
        return try IssuerSigned.decode(bytes)
    }

    private func held(_ area: SoftwareSecureArea, _ issuerSigned: IssuerSigned, _ deviceKey: KeyInfo,
                      _ binder: MdocTransactionDataBinder?) throws -> HeldMdoc {
        try HeldMdoc(credentialId: "mdl", issuerSigned: issuerSigned,
                     deviceSigner: SecureAreaCoseSigner(area: area, key: deviceKey.handle, algorithm: .es256),
                     transactionDataBinder: binder)
    }

    private func ctx(_ rawTx: String) -> PresentationContext {
        PresentationContext(disclosedPaths: [[namespace, "family_name"]], clientId: "verifier", nonce: "n",
                            responseUri: "https://v.example/cb", issuedAt: 1_700_000_000, transactionData: [rawTx],
                            verifierJwkThumbprint: nil)
    }

    private func tx(_ type: String) -> String { Base64Url.encode([UInt8](#"{"type":"\#(type)","credential_ids":["mdl"]}"#.utf8)) }

    /// Binds a "payment" transaction to the device-signed element `ns`/`id`.
    private func binder(_ ns: String, _ id: String) -> MdocTransactionDataBinder {
        { td in td.type == "payment" ? DeviceSignedTransactionData(namespace: ns, elementId: id, value: .text("authorized")) : nil }
    }

    private func field(_ c: Cbor, _ key: String) -> Cbor? {
        guard case let .map(entries) = c else { return nil }
        return entries.first { if case let .text(t) = $0.0 { return t == key }; return false }?.1
    }

    private func deviceSignedElement(_ presentation: String, _ ns: String, _ id: String) throws -> Cbor? {
        let deviceResponse = try CborDecoder.decode(Base64Url.decode(presentation))
        guard case let .array(documents)? = field(deviceResponse, "documents") else { return nil }
        guard case let .tagged(_, .bytes(nsBytes))? = field(field(documents[0], "deviceSigned")!, "nameSpaces") else { return nil }
        let nsMap = try CborDecoder.decode(nsBytes)
        guard let nsEntry = field(nsMap, ns) else { return nil }
        return field(nsEntry, id)
    }

    func testBindsAuthorizedTransactionDataAsDeviceSignedElement() async throws {
        let area = SoftwareSecureArea()
        let issuerKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let deviceKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let issuerSigned = try await mdoc(area, issuerKey, deviceKey.publicKey, authorized: [namespace: ["tx_auth"]])

        let presentation = try await held(area, issuerSigned, deviceKey, binder(namespace, "tx_auth")).present(ctx(tx("payment")))

        XCTAssertEqual(Cbor.text("authorized"), try deviceSignedElement(presentation, namespace, "tx_auth"),
                       "the authorized transaction_data element is device-signed into the response")
    }

    func testRejectsElementNotAuthorizedByMso() async throws {
        let area = SoftwareSecureArea()
        let issuerKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let deviceKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        // MSO authorizes tx_auth, but the binder returns tx_other → unauthorized.
        let issuerSigned = try await mdoc(area, issuerKey, deviceKey.publicKey, authorized: [namespace: ["tx_auth"]])
        let h = try held(area, issuerSigned, deviceKey, binder(namespace, "tx_other"))
        await assertInvalidTransactionData { _ = try await h.present(self.ctx(self.tx("payment"))) }
    }

    func testRejectsUnsupportedTypeAndMissingBinder() async throws {
        let area = SoftwareSecureArea()
        let issuerKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let deviceKey = try await area.createKey(spec: KeySpec(secureArea: area.id, algorithm: .es256))
        let issuerSigned = try await mdoc(area, issuerKey, deviceKey.publicKey, authorized: [namespace: ["tx_auth"]])

        let withBinder = try held(area, issuerSigned, deviceKey, binder(namespace, "tx_auth"))
        await assertInvalidTransactionData { _ = try await withBinder.present(self.ctx(self.tx("unknown_type"))) }
        let noBinder = try held(area, issuerSigned, deviceKey, nil)
        await assertInvalidTransactionData { _ = try await noBinder.present(self.ctx(self.tx("payment"))) }
    }

    private func assertInvalidTransactionData(_ body: () async throws -> Void) async {
        do { try await body(); XCTFail("expected invalidTransactionData") }
        catch VpError.invalidTransactionData {} catch { XCTFail("wrong error: \(error)") }
    }
}
