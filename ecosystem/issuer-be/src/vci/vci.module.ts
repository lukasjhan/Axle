import { Module } from '@nestjs/common';
import { CredentialsModule } from '../credentials/credentials.module';
import { StatusListModule } from '../status-list/status-list.module';
import { KeyAttestationService } from '../attestation/key-attestation.service';
import { WalletAttestationGuard } from '../attestation/wallet-attestation.guard';
import { DpopGuard } from '../dpop/dpop.guard';
import { DpopNonceService } from '../dpop/dpop-nonce.service';
import { MetadataService } from './metadata.service';
import { VciService } from './vci.service';
import { VciController } from './vci.controller';
import { WellKnownController } from './well-known.controller';

@Module({
  imports: [CredentialsModule, StatusListModule],
  controllers: [WellKnownController, VciController],
  providers: [VciService, MetadataService, KeyAttestationService, DpopNonceService, WalletAttestationGuard, DpopGuard],
})
export class VciModule {}
