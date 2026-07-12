import { Controller, Get } from '@nestjs/common';
import { MetadataService } from './metadata.service';

/**
 * OpenID4VCI / OAuth metadata. These routes are excluded from the /eudi-issuer global prefix (see main.ts):
 * RFC 8414 places the well-known segment at the origin root with the issuer path segment appended.
 */
@Controller()
export class WellKnownController {
  constructor(private readonly metadata: MetadataService) {}

  @Get('.well-known/openid-credential-issuer/eudi-issuer')
  credentialIssuer() {
    return this.metadata.credentialIssuerMetadata();
  }

  @Get('.well-known/oauth-authorization-server/eudi-issuer')
  authorizationServer() {
    return this.metadata.authorizationServerMetadata();
  }
}
