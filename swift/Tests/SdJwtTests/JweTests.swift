import CborCose
import Crypto
import Foundation
import XCTest
@testable import SdJwt

final class JweTests: XCTestCase {

    func testConcatKdfMatchesRfc7518AppendixC() {
        // RFC 7518 Appendix C — ECDH-ES key agreement worked example.
        let z: [UInt8] = [
            158, 86, 217, 29, 129, 113, 53, 211, 114, 131, 66, 131, 191, 132, 38, 156,
            251, 49, 110, 163, 218, 128, 106, 72, 246, 218, 167, 121, 140, 254, 144, 196,
        ]
        let derived = Jwe.concatKdf(z: z, keyBytes: 16, algId: "A128GCM", apu: [UInt8]("Alice".utf8), apv: [UInt8]("Bob".utf8))
        XCTAssertEqual("VqqN6vgjbSBcIijNcacQGg", Base64Url.encode(derived))
    }

    func testEncryptDecryptRoundtrip() throws {
        for enc in [JweEnc.a128gcm, .a256gcm] {
            let priv = P256.KeyAgreement.PrivateKey()
            let raw = priv.publicKey.rawRepresentation // x||y
            let recipient = EcPublicKey(curve: .p256, x: [UInt8](raw.prefix(32)), y: [UInt8](raw.suffix(32)))
            let d = [UInt8](priv.rawRepresentation)

            let plaintext = [UInt8](#"{"vp_token":{"pid":["eyJ...~"]},"state":"abc"}"#.utf8)
            let jwe = try Jwe.encryptEcdhEs(plaintext: plaintext, recipient: recipient, enc: enc, apu: [UInt8]("wallet".utf8))
            XCTAssertEqual(5, jwe.split(separator: ".", omittingEmptySubsequences: false).count)

            let decrypted = try Jwe.decryptEcdhEs(jwe, recipientPrivateD: d)
            XCTAssertEqual(plaintext, decrypted)
        }
    }

    func testTamperedCiphertextFails() throws {
        let priv = P256.KeyAgreement.PrivateKey()
        let raw = priv.publicKey.rawRepresentation
        let recipient = EcPublicKey(curve: .p256, x: [UInt8](raw.prefix(32)), y: [UInt8](raw.suffix(32)))
        let d = [UInt8](priv.rawRepresentation)

        let jwe = try Jwe.encryptEcdhEs(plaintext: [UInt8]("secret".utf8), recipient: recipient)
        var parts = jwe.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var ct = try Base64Url.decode(parts[3])
        ct[0] = ct[0] &+ 1
        parts[3] = Base64Url.encode(ct)
        XCTAssertThrowsError(try Jwe.decryptEcdhEs(parts.joined(separator: "."), recipientPrivateD: d))
    }
}
