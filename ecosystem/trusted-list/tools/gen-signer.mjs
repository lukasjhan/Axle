// Mints a leaf Document Signer (DSC) certificate signed by one of the issuer CAs — the key the Issuer backend
// actually signs credentials with (SD-JWT VC x5c[0] / mdoc x5chain[0]). Per HAIP the leaf is NOT self-signed
// and the trust anchor (the CA) is NOT included; verifiers resolve the CA from the published Trusted List.
// The output keystore (private key + leaf cert + CA cert) is fed to the Issuer via env — keep it offline.
//   node tools/gen-signer.mjs <ca-slug> <signer-slug> "<CN suffix>"
//   e.g. node tools/gen-signer.mjs pid-issuer-ca pid-signer "PID Document Signer"
import 'reflect-metadata';
import { Crypto } from '@peculiar/webcrypto';
import * as x509 from '@peculiar/x509';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const [caSlug, signerSlug, cnSuffix] = process.argv.slice(2);
if (!caSlug || !signerSlug || !cnSuffix) {
  console.error('usage: node tools/gen-signer.mjs <ca-slug> <signer-slug> "<CN suffix>"');
  process.exit(1);
}

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const webcrypto = new Crypto();
x509.cryptoProvider.set(webcrypto);

const ca = JSON.parse(readFileSync(join(root, `secrets/${caSlug}.json`), 'utf8'));
const caCert = new x509.X509Certificate(ca.certPem);
const caKey = await webcrypto.subtle.importKey(
  'pkcs8',
  Buffer.from(ca.privateKeyPem.replace(/-----[^-]+-----|\s/g, ''), 'base64'),
  { name: 'ECDSA', namedCurve: 'P-256' },
  false,
  ['sign'],
);

const now = new Date();
const notAfter = new Date(now);
notAfter.setUTCFullYear(notAfter.getUTCFullYear() + 3); // DSC: 3y (well within the 10y CA)

const keys = await webcrypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const cert = await x509.X509CertificateGenerator.create({
  serialNumber: '02',
  subject: `CN=Hopae S.A. ${cnSuffix}, 2.5.4.97=NTRLU-B000000, O=Hopae S.A., C=LU`,
  issuer: caCert.subject,
  notBefore: new Date(now.getTime() - 24 * 60 * 60 * 1000),
  notAfter,
  publicKey: keys.publicKey,
  signingKey: caKey,
  signingAlgorithm: { name: 'ECDSA', hash: 'SHA-256' },
  extensions: [
    new x509.BasicConstraintsExtension(false, undefined, true), // CA:FALSE
    new x509.KeyUsagesExtension(x509.KeyUsageFlags.digitalSignature, true),
    await x509.SubjectKeyIdentifierExtension.create(keys.publicKey),
    await x509.AuthorityKeyIdentifierExtension.create(caCert), // link to the CA (AKI = CA SKI)
  ],
});

const pkcs8 = Buffer.from(await webcrypto.subtle.exportKey('pkcs8', keys.privateKey)).toString('base64');
const privateKeyPem = `-----BEGIN PRIVATE KEY-----\n${pkcs8.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;

mkdirSync(join(root, 'secrets'), { recursive: true });
writeFileSync(
  join(root, `secrets/${signerSlug}.json`),
  JSON.stringify({ privateKeyPem, certPem: cert.toString('pem') + '\n', caCertPem: ca.certPem }, null, 2),
);

console.log(`wrote secrets/${signerSlug}.json (private, gitignored)`);
console.log('DSC   :', cert.subjectName.toString());
console.log('issuer:', caCert.subjectName.toString(), '| valid', now.toISOString().slice(0, 10), '→', notAfter.toISOString().slice(0, 10));
