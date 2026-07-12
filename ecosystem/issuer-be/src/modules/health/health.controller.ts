import { Controller, Get } from '@nestjs/common';
import { HealthCheck, HealthCheckService, MemoryHealthIndicator } from '@nestjs/terminus';
import { DbHealthIndicator } from './db-health.indicator';

@Controller()
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private memory: MemoryHealthIndicator,
    private db: DbHealthIndicator,
  ) {}

  @Get('health')
  @HealthCheck()
  checkHealth() {
    return this.health.check([]);
  }

  @Get('live')
  @HealthCheck()
  checkLive() {
    return this.health.check([() => this.memory.checkHeap('memory_heap', 512 * 1024 * 1024)]);
  }

  @Get('ready')
  @HealthCheck()
  checkReady() {
    return this.health.check([() => this.db.isHealthy('database')]);
  }
}
