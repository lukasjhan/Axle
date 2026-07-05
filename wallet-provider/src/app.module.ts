import { Module } from '@nestjs/common';
import { WalletProviderModule } from './wallet-provider/wallet-provider.module';

@Module({
  imports: [WalletProviderModule],
})
export class AppModule {}
