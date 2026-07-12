import { Injectable } from '@nestjs/common';
import { randomBytes } from 'node:crypto';
import { SessionStore } from '../session/session.store';

const TTL_SEC = 300;

/** Server-provided DPoP nonces (RFC 9449 §8/§9), stored in the shared session store so they work multi-replica. */
@Injectable()
export class DpopNonceService {
  constructor(private readonly store: SessionStore) {}

  async issue(): Promise<string> {
    const nonce = randomBytes(24).toString('base64url');
    await this.store.set(`dpop-nonce:${nonce}`, 1, TTL_SEC);
    return nonce;
  }

  async isValid(nonce?: string): Promise<boolean> {
    if (!nonce) return false;
    return (await this.store.get(`dpop-nonce:${nonce}`)) !== null;
  }
}
