// Generates a self-signed issuer CA (trust anchor) for the sandbox — a root the issued credentials chain to.
// The PUBLIC cert goes to config/certs/<slug>.pem (committed, listed in the Trusted List); the private key
// goes to secrets/<slug>.json (gitignored) for the future issuer backend to sign document signers / VCs with.
//   node tools/gen-issuer-ca.mjs <slug> "<CN suffix>"
//   e.g. node tools/gen-issuer-ca.mjs pid-issuer-ca "PID Issuer CA"
import 'reflect-metadata';
import { Crypto } from '@peculiar/webcrypto';
import * as x509 from '@peculiar/x509';
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const [slug, cnSuffix] = process.argv.slice(2);
if (!slug || !cnSuffix) {
  console.error('usage: node tools/gen-issuer-ca.mjs <slug> "<CN suffix>"');
  process.exit(1);
}

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const webcrypto = new Crypto();
x509.cryptoProvider.set(webcrypto);

const now = new Date();
const notAfter = new Date(now);
notAfter.setUTCFullYear(notAfter.getUTCFullYear() + 10); // issuer CA: 10y (matches the WP CA)

const keys = await webcrypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const cert = await x509.X509CertificateGenerator.createSelfSigned({
  serialNumber: '01',
  // Same legal identity as the WP CA: EN 319 412-1 organizationIdentifier (2.5.4.97), Hopae S.A., Luxembourg.
  name: `CN=Hopae S.A. ${cnSuffix}, 2.5.4.97=NTRLU-B000000, O=Hopae S.A., C=LU`,
  keys,
  signingAlgorithm: { name: 'ECDSA', hash: 'SHA-256' },
  notBefore: new Date(now.getTime() - 24 * 60 * 60 * 1000),
  notAfter,
  extensions: [
    new x509.BasicConstraintsExtension(true, undefined, true), // CA:TRUE, critical
    new x509.KeyUsagesExtension(x509.KeyUsageFlags.keyCertSign | x509.KeyUsageFlags.cRLSign, true),
    await x509.SubjectKeyIdentifierExtension.create(keys.publicKey),
  ],
});

const pkcs8 = Buffer.from(await webcrypto.subtle.exportKey('pkcs8', keys.privateKey)).toString('base64');
const privateKeyPem = `-----BEGIN PRIVATE KEY-----\n${pkcs8.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
const certPem = cert.toString('pem') + '\n';

mkdirSync(join(root, 'secrets'), { recursive: true });
mkdirSync(join(root, 'config/certs'), { recursive: true });
writeFileSync(join(root, `secrets/${slug}.json`), JSON.stringify({ privateKeyPem, certPem }, null, 2));
writeFileSync(join(root, `config/certs/${slug}.pem`), certPem);

console.log(`wrote config/certs/${slug}.pem (public) + secrets/${slug}.json (private, gitignored)`);
console.log('CA:', cert.subjectName.toString(), '| valid', now.toISOString().slice(0, 10), '→', notAfter.toISOString().slice(0, 10));
