import { Module } from '@nestjs/common';
import { AttestationService } from './attestation.service';
import { InstanceRepository } from './instance.repository';
import { IntegrityService } from './integrity.service';
import { KeystoreService } from './keystore.service';
import { NonceService } from './nonce.service';
import { WalletProviderController } from './wallet-provider.controller';

/** ARF Wallet Provider: registers wallet instances and issues WUA + key attestations. */
@Module({
  controllers: [WalletProviderController],
  providers: [KeystoreService, NonceService, IntegrityService, InstanceRepository, AttestationService],
})
export class WalletProviderModule {}
