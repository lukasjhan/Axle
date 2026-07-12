import { Injectable, Inject } from '@nestjs/common';
import { HealthIndicatorService } from '@nestjs/terminus';
import { sql } from 'drizzle-orm';
import { DRIZZLE, type DrizzleDb } from '../../db/drizzle.module';

@Injectable()
export class DbHealthIndicator {
  constructor(
    @Inject(DRIZZLE) private readonly db: DrizzleDb,
    private readonly indicator: HealthIndicatorService,
  ) {}

  async isHealthy(key: string) {
    const check = this.indicator.check(key);
    try {
      await this.db.execute(sql`SELECT 1`);
      return check.up();
    } catch (error) {
      return check.down({ message: (error as Error).message });
    }
  }
}
