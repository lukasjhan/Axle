import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

/**
 * Short-lived protocol state (PAR requests, authorization codes, auth interactions, access/refresh tokens,
 * DPoP/c_nonces, replay-protection jtis). Redis-backed when `REDIS_URL` is set (required for multi-replica),
 * otherwise an in-memory Map with lazy TTL expiry (single-replica dev). Values are JSON.
 */
@Injectable()
export class SessionStore implements OnModuleDestroy {
  private readonly logger = new Logger(SessionStore.name);
  private readonly redis?: Redis;
  private readonly mem = new Map<string, { v: string; exp: number }>();

  constructor(config: ConfigService) {
    const url = config.get<string>('REDIS_URL');
    if (url) {
      this.redis = new Redis(url, { maxRetriesPerRequest: 3, lazyConnect: false });
      this.redis.on('error', (e) => this.logger.error(`redis: ${e.message}`));
      this.logger.log('session state: Redis');
    } else {
      this.logger.warn('REDIS_URL unset — using in-memory session state (single-replica only)');
    }
  }

  async set(key: string, value: unknown, ttlSec: number): Promise<void> {
    const json = JSON.stringify(value);
    if (this.redis) {
      await this.redis.set(key, json, 'EX', ttlSec);
    } else {
      this.mem.set(key, { v: json, exp: Date.now() + ttlSec * 1000 });
    }
  }

  async get<T>(key: string): Promise<T | null> {
    if (this.redis) {
      const v = await this.redis.get(key);
      return v ? (JSON.parse(v) as T) : null;
    }
    const e = this.mem.get(key);
    if (!e) return null;
    if (e.exp < Date.now()) {
      this.mem.delete(key);
      return null;
    }
    return JSON.parse(e.v) as T;
  }

  /** Atomic read-and-delete (single-use codes/nonces). */
  async getdel<T>(key: string): Promise<T | null> {
    if (this.redis) {
      const v = await this.redis.getdel(key);
      return v ? (JSON.parse(v) as T) : null;
    }
    const v = await this.get<T>(key);
    this.mem.delete(key);
    return v;
  }

  async del(key: string): Promise<void> {
    if (this.redis) await this.redis.del(key);
    else this.mem.delete(key);
  }

  /** Set a replay marker if absent; returns true if it was newly set (i.e. not a replay). */
  async setOnce(key: string, ttlSec: number): Promise<boolean> {
    if (this.redis) {
      const res = await this.redis.set(key, '1', 'EX', ttlSec, 'NX');
      return res === 'OK';
    }
    if (await this.get(key)) return false;
    await this.set(key, 1, ttlSec);
    return true;
  }

  async onModuleDestroy() {
    await this.redis?.quit();
  }
}
