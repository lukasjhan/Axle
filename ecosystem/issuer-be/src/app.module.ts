import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { LoggerModule } from 'nestjs-pino';
import { PrometheusModule } from '@willsoto/nestjs-prometheus';
import { validate } from './env.validation';
import { createLoggerConfig } from './logger.config';
import { DrizzleModule } from './db/drizzle.module';
import { HealthModule } from './modules/health/health.module';
import { MetricsModule } from './modules/metrics/metrics.module';
import { CryptoModule } from './crypto/crypto.module';
import { CredentialsModule } from './credentials/credentials.module';
import { SessionModule } from './session/session.module';
import { JwtModule } from './jwt/jwt.module';
import { TrustModule } from './trust/trust.module';
import { StatusListModule } from './status-list/status-list.module';
import { VciModule } from './vci/vci.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate }),
    LoggerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => createLoggerConfig(config),
    }),
    DrizzleModule,
    PrometheusModule.register({ defaultMetrics: { enabled: true } }),
    MetricsModule,
    HealthModule,
    CryptoModule,
    CredentialsModule,
    SessionModule,
    JwtModule,
    TrustModule,
    StatusListModule,
    VciModule,
  ],
})
export class AppModule {}
