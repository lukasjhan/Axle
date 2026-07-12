import { Module } from '@nestjs/common';
import { TerminusModule } from '@nestjs/terminus';
import { HealthController } from './health.controller';
import { DbHealthIndicator } from './db-health.indicator';

@Module({
  imports: [TerminusModule],
  controllers: [HealthController],
  providers: [DbHealthIndicator],
})
export class HealthModule {}
