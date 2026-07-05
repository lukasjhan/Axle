import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { JWK } from 'jose';

export interface WalletInstance {
  instanceId: string;
  publicJwk: JWK; // the wallet instance key (bound into the WUA cnf)
  platform: string;
  createdAt: number;
  revoked: boolean;
}

/**
 * Registry of wallet instances. In-memory for dev; the interface is the DB seam
 * (swap for Postgres/Prisma without touching callers).
 */
@Injectable()
export class InstanceRepository {
  private readonly byId = new Map<string, WalletInstance>();

  create(publicJwk: JWK, platform: string): WalletInstance {
    const instance: WalletInstance = {
      instanceId: randomUUID(),
      publicJwk,
      platform,
      createdAt: Date.now(),
      revoked: false,
    };
    this.byId.set(instance.instanceId, instance);
    return instance;
  }

  get(instanceId: string): WalletInstance | undefined {
    return this.byId.get(instanceId);
  }

  revoke(instanceId: string): boolean {
    const instance = this.byId.get(instanceId);
    if (!instance) return false;
    instance.revoked = true;
    return true;
  }
}
