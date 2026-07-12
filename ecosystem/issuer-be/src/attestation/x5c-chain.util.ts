import * as x509 from '@peculiar/x509';
import { Crypto } from '@peculiar/webcrypto';
import { exportJWK, type JWK } from 'jose';

const webcrypto = new Crypto();
x509.cryptoProvider.set(webcrypto);

/**
 * Verifies an `x5c` chain (base64 DER, leaf first) up to one of the trust anchors and returns the leaf's
 * public key as a JWK. HAIP requires the leaf to be non-self-signed and the trust anchor to be excluded from
 * `x5c`, so the top of the chain must be *signed by* (or equal to) an anchor.
 */
export async function verifyX5cToAnchors(
  x5c: string[],
  anchors: x509.X509Certificate[],
  date: Date = new Date(),
): Promise<JWK> {
  if (!x5c?.length) throw new Error('empty x5c');
  const chain = x5c.map((b64) => new x509.X509Certificate(b64));
  const leaf = chain[0];

  if (chain.length === 1 && leaf.issuer === leaf.subject) {
    throw new Error('leaf certificate must not be self-signed (HAIP)');
  }

  // Each cert must be signed by the next one in the chain.
  for (let i = 0; i < chain.length - 1; i++) {
    if (!(await chain[i].verify({ publicKey: chain[i + 1].publicKey, date }))) {
      throw new Error(`broken x5c link at depth ${i}`);
    }
  }

  // The top of the provided chain must be issued by (or equal to) a trust anchor.
  const top = chain[chain.length - 1];
  const topDer = Buffer.from(top.rawData).toString('base64');
  let anchored = false;
  for (const a of anchors) {
    // Compare by raw DER rather than `a.equal(top)` — the latter's `is this` type predicate would narrow
    // `top` to `never` in the following branch.
    if (Buffer.from(a.rawData).toString('base64') === topDer) {
      anchored = true;
      break;
    }
    if (top.issuer === a.subject && (await top.verify({ publicKey: a.publicKey, date }))) {
      anchored = true;
      break;
    }
  }
  if (!anchored) throw new Error('x5c does not chain to a trusted anchor');

  const pub = await leaf.publicKey.export(webcrypto);
  return exportJWK(pub);
}
