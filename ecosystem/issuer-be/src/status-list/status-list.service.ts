import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { eq } from 'drizzle-orm';
import { DRIZZLE, type DrizzleDb } from '../db/drizzle.module';
import { issuedCredentials } from '../db/schema';
import { IssuerJwtService } from '../jwt/issuer-jwt.service';
import { encodeStatusList, statusListUri, STATUS_INVALID, STATUS_LIST_ID, STATUS_VALID } from './status-list.codec';

/**
 * The Issuer's Token Status List (IETF draft-ietf-oauth-status-list). Every issued credential gets a unique,
 * monotonic index (the DB identity column); the status list token is the DEFLATE-packed bit array of all
 * indices' statuses, signed as `statuslist+jwt` with the Issuer DSC (x5c) so relying parties can verify it.
 */
@Injectable()
export class StatusListService {
  constructor(
    @Inject(DRIZZLE) private readonly db: DrizzleDb,
    private readonly issuerJwt: IssuerJwtService,
    private readonly config: ConfigService,
  ) {}

  private get issuer(): string {
    return this.config.getOrThrow<string>('ISSUER_BASE_URL');
  }

  /** Record a freshly issued credential and return its status list reference for the `status` claim. */
  async recordIssuance(configId: string, format: string, holderJkt?: string): Promise<{ idx: number; uri: string }> {
    const [row] = await this.db
      .insert(issuedCredentials)
      .values({ configId, format, holderJkt })
      .returning({ statusIdx: issuedCredentials.statusIdx });
    return { idx: row.statusIdx, uri: statusListUri(this.issuer, STATUS_LIST_ID) };
  }

  /** Build + sign the Status List Token (JWT) for the given list id. */
  async statusListToken(id: string = STATUS_LIST_ID): Promise<string> {
    const rows = await this.db
      .select({ idx: issuedCredentials.statusIdx, status: issuedCredentials.status })
      .from(issuedCredentials);
    const statusList = encodeStatusList(rows, 1, 256);
    return this.issuerJwt.sign(
      { status_list: statusList, ttl: 3600 },
      { typ: 'statuslist+jwt', sub: statusListUri(this.issuer, id), expSec: 3600, x5c: true },
    );
  }

  /** Flip a credential to INVALID (revoked) by its status index. */
  async revoke(statusIdx: number): Promise<boolean> {
    const res = await this.db
      .update(issuedCredentials)
      .set({ status: STATUS_INVALID, revokedAt: new Date() })
      .where(eq(issuedCredentials.statusIdx, statusIdx))
      .returning({ statusIdx: issuedCredentials.statusIdx });
    return res.length > 0;
  }

  /** Restore a credential to VALID. */
  async unrevoke(statusIdx: number): Promise<boolean> {
    const res = await this.db
      .update(issuedCredentials)
      .set({ status: STATUS_VALID, revokedAt: null })
      .where(eq(issuedCredentials.statusIdx, statusIdx))
      .returning({ statusIdx: issuedCredentials.statusIdx });
    return res.length > 0;
  }
}
