// Generates the Wallet Provider signing keystore (CA + signer) ONCE. Copy the printed values into your
// deployment secret (raw PEM) or local .env (\n-escaped). Keeping these stable is what lets a WUA issued by
// one replica/boot verify against another — see KeystoreService.
//   cd wallet-provider && node tools/gen-keystore.mjs
import 'reflect-metadata'; // @peculiar/x509 (via tsyringe) needs the reflect polyfill loaded first
import { Crypto } from '@peculiar/webcrypto';
import * as x509 from '@peculiar/x509';

const webcrypto = new Crypto();
x509.cryptoProvider.set(webcrypto);

const alg = { name: 'ECDSA', namedCurve: 'P-256' };
const sigAlg = { name: 'ECDSA', hash: 'SHA-256' };
// Issued from now: CA valid 10y, signer 3y (signing certs are rotated more often). Backdate 1 day for skew.
const now = new Date();
const inYears = (y) => { const d = new Date(now); d.setUTCFullYear(d.getUTCFullYear() + y); return d; };
const notBefore = new Date(now.getTime() - 24 * 60 * 60 * 1000);
const caValidity = { notBefore, notAfter: inYears(10) };
const signerValidity = { notBefore, notAfter: inYears(3) };

const caKeys = await webcrypto.subtle.generateKey(alg, true, ['sign', 'verify']);
const signKeys = await webcrypto.subtle.generateKey(alg, true, ['sign', 'verify']);

// ETSI TS 119 602 Annex E: the listed WP cert must carry the provider's name (organizationName = TE name)
// and, where applicable, its registration number (organizationIdentifier 2.5.4.97, EN 319 412-1 format:
// <3-char scheme><2-char country>-<id>, e.g. VATSE-556677889900). Adjust to your real registration.
const org = process.env.WP_ORG_NAME || 'Hopae S.A.';
const orgId = process.env.WP_ORG_ID || 'NTRLU-B000000'; // placeholder — set to the real RCS Luxembourg number
const country = process.env.WP_COUNTRY || 'LU';
const dn = (cn) => `CN=${cn}, 2.5.4.97=${orgId}, O=${org}, C=${country}`; // 2.5.4.97 = organizationIdentifier

const caCert = await x509.X509CertificateGenerator.createSelfSigned({
  serialNumber: '01',
  name: dn(`${org} EUDI Wallet Provider CA`),
  keys: caKeys,
  signingAlgorithm: sigAlg,
  extensions: [
    new x509.BasicConstraintsExtension(true, 1, true),
    new x509.KeyUsagesExtension(x509.KeyUsageFlags.keyCertSign | x509.KeyUsageFlags.cRLSign, true),
    await x509.SubjectKeyIdentifierExtension.create(caKeys.publicKey),
  ],
  ...caValidity,
});

const signerCert = await x509.X509CertificateGenerator.create({
  serialNumber: '02',
  subject: dn(`${org} Wallet Unit Attestation Signer`),
  issuer: caCert.subject,
  publicKey: signKeys.publicKey,
  signingKey: caKeys.privateKey,
  signingAlgorithm: sigAlg,
  extensions: [
    new x509.BasicConstraintsExtension(false),
    new x509.KeyUsagesExtension(x509.KeyUsageFlags.digitalSignature, true),
    await x509.SubjectKeyIdentifierExtension.create(signKeys.publicKey),
    await x509.AuthorityKeyIdentifierExtension.create(caKeys.publicKey),
  ],
  ...signerValidity,
});

const pkcs8 = Buffer.from(await webcrypto.subtle.exportKey('pkcs8', signKeys.privateKey)).toString('base64');
const norm = (pem) => pem.trim() + '\n';
const signerKeyPem = norm(`-----BEGIN PRIVATE KEY-----\n${pkcs8.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----`);
const signerCertPem = norm(signerCert.toString('pem'));
const caCertPem = norm(caCert.toString('pem'));
const esc = (s) => s.replace(/\n/g, '\\n');

console.log('# ─── raw PEM — for a k8s / AWS Secrets Manager multi-line secret ───\n');
console.log('WP_SIGNER_PRIVATE_KEY:\n' + signerKeyPem);
console.log('WP_SIGNER_CERT:\n' + signerCertPem);
console.log('WP_CA_CERT:\n' + caCertPem);
console.log('# ─── single-line \\n-escaped — for .env ───\n');
console.log(`WP_SIGNER_PRIVATE_KEY='${esc(signerKeyPem)}'`);
console.log(`WP_SIGNER_CERT='${esc(signerCertPem)}'`);
console.log(`WP_CA_CERT='${esc(caCertPem)}'`);
