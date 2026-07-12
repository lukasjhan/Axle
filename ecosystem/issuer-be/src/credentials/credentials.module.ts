import { Module } from '@nestjs/common';
import { SdJwtService } from './sd-jwt.service';
import { MdocService } from './mdoc.service';

@Module({
  providers: [SdJwtService, MdocService],
  exports: [SdJwtService, MdocService],
})
export class CredentialsModule {}
