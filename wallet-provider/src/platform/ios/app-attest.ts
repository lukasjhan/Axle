import 'reflect-metadata';
import { createHash } from 'crypto';
import { Crypto } from '@peculiar/webcrypto';
import * as x509 from '@peculiar/x509';
import { APPLE_APP_ATTEST_ROOT_CA_PEM } from './apple-app-attest-root';
import type { IntegrityResult } from '../platform-verifier';

x509.cryptoProvider.set(new Crypto());

/** Apple's App Attest nonce extension (a DER `SEQUENCE { [1] OCTET STRING }` carrying the expected nonce). */
const APP_ATTEST_NONCE_OID = '1.2.840.113635.100.8.2';

/**
 * Verifies an Apple App Attest attestation (the `attestKey` object) against the wallet-provider challenge,
 * following Apple's "Validating Apps That Connect to Your Server". Confirms a genuine, unmodified instance of
 * our app on a real device produced the attested key bound to `challenge`. Unlike Android Play Integrity this
 * is a local cryptographic check (attestation certificate chain), no Apple round-trip.
 */
export async function verifyAppAttest(
  attestation: Buffer,
  keyId: string, // base64 credentialId = SHA-256 of the attested public key
  challenge: string, // the wallet-provider nonce
  appId: string, // "<TEAM_ID>.<BUNDLE_ID>"
): Promise<IntegrityResult> {
  try {
    const obj = new CborReader(attestation).read() as {
      fmt?: string;
      attStmt?: { x5c?: Buffer[]; receipt?: Buffer };
      authData?: Buffer;
    };
    if (obj?.fmt !== 'apple-appattest') return fail('unexpected attestation format');
    const x5c = obj.attStmt?.x5c;
    const authData = obj.authData;
    if (!Array.isArray(x5c) || x5c.length < 1 || !Buffer.isBuffer(authData)) return fail('malformed attestation');

    // 1. Certificate chain: credCert → intermediate(s) → the pinned Apple App Attest root.
    const certs = x5c.map((der) => new x509.X509Certificate(new Uint8Array(der)));
    const root = new x509.X509Certificate(APPLE_APP_ATTEST_ROOT_CA_PEM);
    const now = new Date();
    for (const c of certs) {
      if (now < c.notBefore || now > c.notAfter) return fail('attestation certificate expired or not yet valid');
    }
    for (let i = 0; i < certs.length - 1; i++) {
      if (!(await certs[i].verify({ publicKey: certs[i + 1].publicKey, signatureOnly: true }))) {
        return fail('attestation certificate chain is invalid');
      }
    }
    if (!(await certs[certs.length - 1].verify({ publicKey: root.publicKey, signatureOnly: true }))) {
      return fail('attestation is not rooted in the Apple App Attest CA');
    }
    const credCert = certs[0];

    // 2. nonce = SHA256(authData || SHA256(challenge)); must equal the credCert nonce extension.
    const clientDataHash = sha256(Buffer.from(challenge, 'utf8'));
    const expectedNonce = sha256(Buffer.concat([authData, clientDataHash]));
    const certNonce = extractNonceExtension(credCert);
    if (!certNonce || !certNonce.equals(expectedNonce)) return fail('attestation nonce mismatch (challenge not bound)');

    // 3. The key identifier is the SHA-256 of the attested public key (uncompressed EC point).
    const spki = Buffer.from(credCert.publicKey.rawData);
    const rawPoint = spki.subarray(spki.length - 65); // P-256 uncompressed point 0x04||X||Y
    const keyIdBytes = Buffer.from(keyId, 'base64');
    if (!sha256(rawPoint).equals(keyIdBytes)) return fail('key identifier does not match the attested public key');

    // 4. authenticatorData: our app (rpIdHash), a genuine App Attest key (aaguid), fresh (counter 0), same key id.
    const rpIdHash = authData.subarray(0, 32);
    if (!rpIdHash.equals(sha256(Buffer.from(appId, 'utf8')))) return fail('rpId hash mismatch (wrong app id)');
    if (authData.readUInt32BE(33) !== 0) return fail('unexpected attestation counter');
    const aaguid = authData.subarray(37, 53).toString('utf8').replace(/\0+$/, '');
    if (aaguid !== 'appattest' && aaguid !== 'appattestdevelop') return fail(`unexpected aaguid: ${aaguid}`);
    const credIdLen = authData.readUInt16BE(53);
    if (!authData.subarray(55, 55 + credIdLen).equals(keyIdBytes)) return fail('credential id does not match key identifier');

    return { trusted: true, platform: 'ios' };
  } catch (e) {
    return fail(`App Attest verification error: ${(e as Error).message}`);
  }
}

function fail(reason: string): IntegrityResult {
  return { trusted: false, platform: 'ios', reason };
}

function sha256(data: Buffer): Buffer {
  return createHash('sha256').update(data).digest();
}

/** The nonce OCTET STRING inside the credCert's App Attest extension (`SEQUENCE { [1] OCTET STRING }`). */
function extractNonceExtension(cert: x509.X509Certificate): Buffer | null {
  const ext = cert.extensions.find((e) => e.type === APP_ATTEST_NONCE_OID);
  if (!ext) return null;
  const v = Buffer.from(ext.value);
  // Expected DER: 30 24 A1 22 04 20 <32 bytes>.
  if (v.length >= 38 && v[4] === 0x04 && v[5] === 0x20) return v.subarray(6, 38);
  const idx = v.indexOf(Buffer.from([0x04, 0x20]));
  return idx >= 0 && idx + 34 <= v.length ? v.subarray(idx + 2, idx + 34) : null;
}

/**
 * Minimal CBOR decoder for the App Attest attestation object (unsigned ints, byte/text strings, arrays,
 * string-keyed maps — the only types Apple's attestation uses).
 */
class CborReader {
  constructor(
    private readonly buf: Buffer,
    private pos = 0,
  ) {}

  read(): unknown {
    const first = this.buf[this.pos++];
    const major = first >> 5;
    const info = first & 0x1f;
    switch (major) {
      case 0:
        return this.length(info); // unsigned int
      case 2: {
        const n = this.length(info);
        const b = Buffer.from(this.buf.subarray(this.pos, this.pos + n));
        this.pos += n;
        return b; // byte string
      }
      case 3: {
        const n = this.length(info);
        const s = this.buf.toString('utf8', this.pos, this.pos + n);
        this.pos += n;
        return s; // text string
      }
      case 4: {
        const n = this.length(info);
        return Array.from({ length: n }, () => this.read()); // array
      }
      case 5: {
        const n = this.length(info);
        const map: Record<string, unknown> = {};
        for (let i = 0; i < n; i++) {
          const key = this.read();
          map[String(key)] = this.read();
        }
        return map; // map
      }
      default:
        throw new Error(`unsupported CBOR major type ${major}`);
    }
  }

  private length(info: number): number {
    if (info < 24) return info;
    if (info === 24) return this.buf[this.pos++];
    if (info === 25) {
      const v = this.buf.readUInt16BE(this.pos);
      this.pos += 2;
      return v;
    }
    if (info === 26) {
      const v = this.buf.readUInt32BE(this.pos);
      this.pos += 4;
      return v;
    }
    if (info === 27) {
      const v = Number(this.buf.readBigUInt64BE(this.pos));
      this.pos += 8;
      return v;
    }
    throw new Error(`unsupported CBOR length info ${info}`);
  }
}
