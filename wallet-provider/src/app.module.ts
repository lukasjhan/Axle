import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { validate } from './env.validation';
import { DrizzleModule } from './db/drizzle.module';
import { HealthModule } from './modules/health/health.module';
import { WalletProviderModule } from './wallet-provider/wallet-provider.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate }),
    DrizzleModule,
    HealthModule,
    WalletProviderModule,
  ],
})
export class AppModule {}
