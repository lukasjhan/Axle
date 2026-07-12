import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
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
import * as jose from 'jose';

const webcrypto = new Crypto();
x509.cryptoProvider.set(webcrypto);

// EN 319 412-3 legal-person identity, aligned with the Wallet Providers Trusted List entity
// (ecosystem/trusted-list/config/lists/wallet-providers.json). Same env knobs as tools/gen-keystore.mjs.
const WP_ORG = process.env.WP_ORG_NAME || 'Hopae S.A.';
const WP_ORG_ID = process.env.WP_ORG_ID || 'NTRLU-B000000'; // organizationIdentifier (EN 319 412-1 format)
const WP_COUNTRY = process.env.WP_COUNTRY || 'LU';
const wpDn = (cn: string): string => `CN=${cn}, 2.5.4.97=${WP_ORG_ID}, O=${WP_ORG}, C=${WP_COUNTRY}`;

// ETSI TS 119 412-6 §5.2 (WAL-5.2-01) + Annex A — a Wallet Provider sign/seal certificate is marked by a
// QCStatements extension carrying the QcType `id-etsi-qct-wal`. Hand-encoded because
// @peculiar/asn1-x509-qualified is not installed and asn1js is not a direct dependency.
// NOTE: keep this in sync with tools/gen-keystore.mjs (the persistent-key generator uses the same encoding).
const ID_QC_STATEMENTS = '1.3.6.1.5.5.7.1.3'; // id-pe-qcStatements (RFC 3739)
const ID_ETSI_QCS_QCTYPE = '0.4.0.1862.1.6'; // id-etsi-qcs-QcType (ETSI EN 319 412-5)
const ID_ETSI_QCT_WAL = '0.4.0.194126.1.2'; // id-etsi-qct-wal (ETSI TS 119 412-6 Annex A)

function derLen(len: number): number[] {
  if (len < 0x80) return [len];
  const out: number[] = [];
  for (let n = len; n > 0; n = Math.floor(n / 256)) out.unshift(n & 0xff);
  return [0x80 | out.length, ...out];
}
const derTlv = (tag: number, body: number[]): number[] => [tag, ...derLen(body.length), ...body];
function derOid(dotted: string): number[] {
  const p = dotted.split('.').map(Number);
  const body = [40 * p[0] + p[1]];
  for (let i = 2; i < p.length; i++) {
    const stack = [p[i] & 0x7f];
    for (let v = Math.floor(p[i] / 128); v > 0; v = Math.floor(v / 128)) stack.unshift((v & 0x7f) | 0x80);
    body.push(...stack);
  }
  return derTlv(0x06, body);
}
const derSeq = (...items: number[][]): number[] => derTlv(0x30, items.flat());

/** QCStatements ::= SEQUENCE OF QCStatement — a single QcType statement whose value is `id-etsi-qct-wal`. */
function walletQcStatementsExtension(): x509.Extension {
  const der = Uint8Array.from(derSeq(derSeq(derOid(ID_ETSI_QCS_QCTYPE), derSeq(derOid(ID_ETSI_QCT_WAL)))));
  return new x509.Extension(ID_QC_STATEMENTS, false, der);
}

/** ETSI TS 119 412-6 §4.4.3 — Authority Information Access with a caIssuers URL to the WP CA certificate. */
function authorityInfoAccessExtension(caIssuerUrl: string): x509.Extension {
  const aia = new AuthorityInfoAccessSyntax([
    new AccessDescription({
      accessMethod: id_ad_caIssuers,
      accessLocation: new GeneralName({ uniformResourceIdentifier: caIssuerUrl }),
    }),
  ]);
  return new x509.Extension(id_pe_authorityInfoAccess, false, AsnConvert.serialize(aia));
}

/** ETSI TS 119 412-6 §5 Wallet Provider sign/seal certificate extensions (shared shape with gen-keystore.mjs). */
async function wpSignerExtensions(signPub: CryptoKey, caPub: CryptoKey, caIssuerUrl: string): Promise<x509.Extension[]> {
  return [
    new x509.BasicConstraintsExtension(false),
    new x509.KeyUsagesExtension(x509.KeyUsageFlags.digitalSignature, true), // §4.4.1 (EN 319 412-2 Table 1)
    await x509.SubjectKeyIdentifierExtension.create(signPub), // §4.4.2
    await x509.AuthorityKeyIdentifierExtension.create(caPub), // RFC 5280 (chain building)
    authorityInfoAccessExtension(caIssuerUrl), // §4.4.3
    walletQcStatementsExtension(), // §5.2 WAL-5.2-01 (id-etsi-qct-wal)
  ];
}

/**
 * Holds the Wallet Provider's signing key and its signer certificate. WUAs / key attestations / status-list
 * tokens carry `x5c = [signer cert]` (convention: the signing leaf only); relying issuers install the WP CA
 * (served at `/ca.pem`) as the trust anchor and chain the signer to it.
 *
 * Production: load the persistent signer key + signer cert + CA cert from env (`WP_SIGNER_PRIVATE_KEY`,
 * `WP_SIGNER_CERT`, `WP_CA_CERT`) so the trust anchor is **stable across restarts and replicas** (generate
 * them once with `tools/gen-keystore.mjs`). Dev: if unset, an ephemeral self-signed CA + signer are made on
 * startup — fine locally, but a fresh key per process, so WUAs won't verify across restarts/replicas.
 */
@Injectable()
export class KeystoreService implements OnModuleInit {
  private readonly logger = new Logger(KeystoreService.name);

  readonly issuer = process.env.WP_ISSUER ?? 'https://wallet-provider.hopae.dev';

  /** jose-usable private signing key. */
  signingKey!: jose.CryptoKey;
  /** base64(DER) chain: `[signer cert]`. The CA is a separately-distributed trust anchor (see `/ca.pem`). */
  x5c!: string[];
  /** signing public key as JWK (for `/jwks`). */
  publicJwk!: jose.JWK;

  private caCertPem!: string;

  async onModuleInit(): Promise<void> {
    const signerKey = pemEnv('WP_SIGNER_PRIVATE_KEY');
    const signerCert = pemEnv('WP_SIGNER_CERT');
    const caCert = pemEnv('WP_CA_CERT');
    if (signerKey && signerCert && caCert) {
      await this.loadFromEnv(signerKey, signerCert, caCert);
      this.logger.log(`WP keystore loaded from env — issuer=${this.issuer}, x5c=[signer]`);
    } else {
      await this.generateEphemeral();
      this.logger.warn(
        'WP keystore generated (ephemeral, per-process) — set WP_SIGNER_PRIVATE_KEY/WP_SIGNER_CERT/WP_CA_CERT to persist the trust anchor across restarts and replicas',
      );
    }
  }

  /** Loads the persistent signer key + certificates from PEM env vars. */
  private async loadFromEnv(signerKeyPem: string, signerCertPem: string, caCertPem: string): Promise<void> {
    this.signingKey = (await jose.importPKCS8(signerKeyPem, 'ES256')) as jose.CryptoKey;
    this.publicJwk = await jose.exportJWK(await jose.importX509(signerCertPem, 'ES256'));
    this.x5c = [pemToBase64Der(signerCertPem)];
    this.caCertPem = caCertPem.trim() + '\n';
  }

  /** Dev fallback: a self-signed CA + signer, freshly generated per process. */
  private async generateEphemeral(): Promise<void> {
    const algorithm: EcKeyGenParams = { name: 'ECDSA', namedCurve: 'P-256' };
    const caKeys = await webcrypto.subtle.generateKey(algorithm, true, ['sign', 'verify']);
    const signKeys = await webcrypto.subtle.generateKey(algorithm, true, ['sign', 'verify']);
    const validity = { notBefore: new Date('2025-01-01'), notAfter: new Date('2035-01-01') };
    const sigAlg: EcdsaParams = { name: 'ECDSA', hash: 'SHA-256' };

    const caCert = await x509.X509CertificateGenerator.createSelfSigned({
      serialNumber: '01',
      name: wpDn('Hopae EUDI Wallet Provider CA'),
      keys: caKeys,
      signingAlgorithm: sigAlg,
      extensions: [
        new x509.BasicConstraintsExtension(true, 1, true),
        new x509.KeyUsagesExtension(x509.KeyUsageFlags.keyCertSign | x509.KeyUsageFlags.cRLSign, true),
        await x509.SubjectKeyIdentifierExtension.create(caKeys.publicKey),
      ],
      ...validity,
    });

    const signerCert = await x509.X509CertificateGenerator.create({
      serialNumber: '02',
      subject: wpDn('Hopae Wallet Unit Attestation Signer'),
      issuer: caCert.subject,
      publicKey: signKeys.publicKey,
      signingKey: caKeys.privateKey,
      signingAlgorithm: sigAlg,
      extensions: await wpSignerExtensions(
        signKeys.publicKey,
        caKeys.publicKey,
        `${this.issuer}/wp/.well-known/wallet-provider-ca.pem`,
      ),
      ...validity,
    });

    const privJwk = (await webcrypto.subtle.exportKey('jwk', signKeys.privateKey)) as jose.JWK;
    this.signingKey = (await jose.importJWK(privJwk, 'ES256')) as jose.CryptoKey;
    this.publicJwk = (await webcrypto.subtle.exportKey('jwk', signKeys.publicKey)) as jose.JWK;
    this.x5c = [Buffer.from(signerCert.rawData).toString('base64')];
    this.caCertPem = caCert.toString('pem');
  }

  /** PEM of the WP CA cert — a relying wallet/issuer installs this as a trust anchor. */
  caPem(): string {
    return this.caCertPem;
  }
}

/** Reads a PEM env var, tolerating single-line `\n`-escaped values (real newlines are unaffected). */
function pemEnv(name: string): string | undefined {
  const value = process.env[name];
  return value ? value.replace(/\\n/g, '\n') : undefined;
}

/** Strips PEM armor + whitespace to the base64(DER) form used in an `x5c` entry. */
function pemToBase64Der(pem: string): string {
  return pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
}
