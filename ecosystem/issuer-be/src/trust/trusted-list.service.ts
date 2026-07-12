import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { X509Certificate, verify as cryptoVerify } from 'node:crypto';
import * as x509 from '@peculiar/x509';

const DEFAULT_URL = 'https://trusted-list.vercel.app/tl/wallet-providers.jades.json';
const CACHE_TTL_MS = 15 * 60 * 1000;

/**
 * Resolves the Wallet Provider CA trust anchors from the JAdES-signed Wallet Providers Trusted List (ETSI TS
 * 119 602) — the anchors a Wallet Unit Attestation (WUA) must chain to. Fetches the list, verifies the Scheme
 * Operator's JAdES signature, extracts each listed service certificate, and caches the result.
 */
@Injectable()
export class TrustedListService {
  private readonly logger = new Logger(TrustedListService.name);
  private readonly url: string;
  private cache?: { cas: x509.X509Certificate[]; at: number };

  constructor(config: ConfigService) {
    this.url = config.get<string>('TRUSTED_LIST_URL') ?? DEFAULT_URL;
  }

  async getWalletProviderCAs(): Promise<x509.X509Certificate[]> {
    if (this.cache && Date.now() - this.cache.at < CACHE_TTL_MS) return this.cache.cas;

    const res = await fetch(this.url, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) throw new Error(`trusted list fetch failed: ${res.status}`);
    const jades = (await res.json()) as { protected: string; payload: string; signature: string };

    this.verifyJades(jades);

    const lote = JSON.parse(Buffer.from(jades.payload, 'base64url').toString()) as {
      trustedEntitiesList: Array<{
        trustedEntityServices: Array<{ serviceDigitalIdentity: { x509Certificate: string } }>;
      }>;
    };
    const cas = lote.trustedEntitiesList.flatMap((e) =>
      e.trustedEntityServices.map((s) => new x509.X509Certificate(s.serviceDigitalIdentity.x509Certificate)),
    );
    this.cache = { cas, at: Date.now() };
    this.logger.log(`trusted list loaded: ${cas.length} Wallet Provider CA(s) from ${this.url}`);
    return cas;
  }

  /** Verify the Scheme Operator's JAdES (ES256) signature over the list, against the embedded x5c[0]. */
  private verifyJades(jades: { protected: string; payload: string; signature: string }): void {
    const header = JSON.parse(Buffer.from(jades.protected, 'base64url').toString());
    const cert = new X509Certificate(`-----BEGIN CERTIFICATE-----\n${header.x5c[0]}\n-----END CERTIFICATE-----`);
    const ok = cryptoVerify(
      'sha256',
      Buffer.from(`${jades.protected}.${jades.payload}`),
      { key: cert.publicKey, dsaEncoding: 'ieee-p1363' },
      Buffer.from(jades.signature, 'base64url'),
    );
    if (!ok) throw new Error('trusted list JAdES signature invalid');
  }
}
