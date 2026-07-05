import { Injectable } from '@nestjs/common';
import { randomBytes } from 'node:crypto';

/** Single-use, short-lived challenge nonces (freshness for registration / attestation PoP). */
@Injectable()
export class NonceService {
  private readonly issued = new Map<string, number>(); // nonce -> expiry epoch ms
  private readonly ttlMs = 5 * 60 * 1000;

  issue(): string {
    this.sweep();
    const nonce = randomBytes(16).toString('base64url');
    this.issued.set(nonce, Date.now() + this.ttlMs);
    return nonce;
  }

  /** Validates and consumes a nonce; returns false if unknown or expired. */
  consume(nonce: string | undefined): boolean {
    if (!nonce) return false;
    const expiry = this.issued.get(nonce);
    this.issued.delete(nonce);
    return expiry !== undefined && expiry > Date.now();
  }

  private sweep(): void {
    const now = Date.now();
    for (const [nonce, expiry] of this.issued) if (expiry <= now) this.issued.delete(nonce);
  }
}
