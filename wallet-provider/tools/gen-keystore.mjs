// Generates the Wallet Provider signing keystore (CA + signer) ONCE. Copy the printed values into your
// deployment secret (raw PEM) or local .env (\n-escaped). Keeping these stable is what lets a WUA issued by
// one replica/boot verify against another — see KeystoreService.
//   cd wallet-provider && node tools/gen-keystore.mjs
import 'reflect-metadata'; // @peculiar/x509 (via tsyringe) needs the reflect polyfill loaded first
import { AsnConvert } from '@peculiar/asn1-schema';
import {
  AccessDescription,
  AuthorityInfoAccessSyntax,
  GeneralName,
  id_ad_caIssuers,
  id_pe_authorityInfoAccess,
} from '@peculiar/asn1-x509';
import { Crypto } from '@peculiar/webcrypto';
import * as x509 from '@peculiar/x509';

const webcrypto = new Crypto();
x509.cryptoProvider.set(webcrypto);

// ETSI TS 119 412-6 §5.2 (WAL-5.2-01) + Annex A — Wallet Provider sign/seal marker: a QCStatements extension
// carrying QcType `id-etsi-qct-wal`. Hand-encoded (asn1-x509-qualified isn't installed).
// NOTE: keep in sync with src/attestation/keystore.service.ts (the ephemeral dev path uses the same encoding).
const ID_QC_STATEMENTS = '1.3.6.1.5.5.7.1.3'; // id-pe-qcStatements
const ID_ETSI_QCS_QCTYPE = '0.4.0.1862.1.6'; // id-etsi-qcs-QcType (EN 319 412-5)
const ID_ETSI_QCT_WAL = '0.4.0.194126.1.2'; // id-etsi-qct-wal (119 412-6 Annex A)
const derLen = (len) => (len < 0x80 ? [len] : (() => { const o = []; for (let n = len; n > 0; n = Math.floor(n / 256)) o.unshift(n & 0xff); return [0x80 | o.length, ...o]; })());
const derTlv = (tag, body) => [tag, ...derLen(body.length), ...body];
const derOid = (dotted) => {
  const p = dotted.split('.').map(Number);
  const body = [40 * p[0] + p[1]];
  for (let i = 2; i < p.length; i++) {
    const stack = [p[i] & 0x7f];
    for (let v = Math.floor(p[i] / 128); v > 0; v = Math.floor(v / 128)) stack.unshift((v & 0x7f) | 0x80);
    body.push(...stack);
  }
  return derTlv(0x06, body);
};
const derSeq = (...items) => derTlv(0x30, items.flat());
const walletQcStatementsExtension = () =>
  new x509.Extension(ID_QC_STATEMENTS, false, Uint8Array.from(derSeq(derSeq(derOid(ID_ETSI_QCS_QCTYPE), derSeq(derOid(ID_ETSI_QCT_WAL))))));
const authorityInfoAccessExtension = (caIssuerUrl) =>
  new x509.Extension(
    id_pe_authorityInfoAccess,
    false,
    AsnConvert.serialize(
      new AuthorityInfoAccessSyntax([
        new AccessDescription({ accessMethod: id_ad_caIssuers, accessLocation: new GeneralName({ uniformResourceIdentifier: caIssuerUrl }) }),
      ]),
    ),
  );

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
const issuerBase = process.env.WP_ISSUER || 'https://wallet-provider.hopae.dev'; // for the AIA caIssuers URL

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
    new x509.KeyUsagesExtension(x509.KeyUsageFlags.digitalSignature, true), // §4.4.1 (EN 319 412-2 Table 1)
    await x509.SubjectKeyIdentifierExtension.create(signKeys.publicKey), // §4.4.2
    await x509.AuthorityKeyIdentifierExtension.create(caKeys.publicKey), // RFC 5280 (chain building)
    authorityInfoAccessExtension(`${issuerBase}/wp/.well-known/wallet-provider-ca.pem`), // §4.4.3
    walletQcStatementsExtension(), // §5.2 WAL-5.2-01 (id-etsi-qct-wal)
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
