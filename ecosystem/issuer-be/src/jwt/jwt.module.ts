import { Global, Module } from '@nestjs/common';
import { IssuerJwtService } from './issuer-jwt.service';

@Global()
@Module({
  providers: [IssuerJwtService],
  exports: [IssuerJwtService],
})
export class JwtModule {}
