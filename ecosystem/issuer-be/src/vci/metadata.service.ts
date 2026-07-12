import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CREDENTIAL_CONFIGS, type CredentialConfig } from './credential-configs';

// HAIP §4.5.1 requires key attestations for high-assurance credentials.
const PROOF_TYPES_SUPPORTED = {
  jwt: {
    proof_signing_alg_values_supported: ['ES256'],
    key_attestations_required: { key_storage: ['iso_18045_moderate', 'iso_18045_high'] },
  },
};

/**
 * Builds the OpenID4VCI 1.0 Credential Issuer metadata and the RFC 8414 Authorization Server metadata from
 * the credential configs. The AS is the Issuer itself. Everything is derived from `ISSUER_BASE_URL` (the
 * credential issuer identifier, which already includes the /eudi-issuer path segment).
 */
@Injectable()
export class MetadataService {
  constructor(private readonly config: ConfigService) {}

  private get iss(): string {
    return this.config.getOrThrow<string>('ISSUER_BASE_URL');
  }

  credentialIssuerMetadata() {
    const iss = this.iss;
    const credential_configurations_supported: Record<string, unknown> = {};
    for (const c of CREDENTIAL_CONFIGS) {
      credential_configurations_supported[c.id] = this.configMetadata(c);
    }
    return {
      credential_issuer: iss,
      authorization_servers: [iss],
      credential_endpoint: `${iss}/credential`,
      nonce_endpoint: `${iss}/nonce`,
      batch_credential_issuance: { batch_size: 1 },
      display: [{ name: 'Hopae EUDI Sandbox Issuer', locale: 'en' }],
      credential_configurations_supported,
    };
  }

  private configMetadata(c: CredentialConfig) {
    const common = {
      scope: c.scope,
      cryptographic_binding_methods_supported: c.format === 'mso_mdoc' ? ['cose_key'] : ['jwk'],
      credential_signing_alg_values_supported: ['ES256'],
      proof_types_supported: PROOF_TYPES_SUPPORTED,
      display: [
        {
          name: c.display.name,
          locale: c.display.locale,
          background_color: c.display.background_color,
          text_color: c.display.text_color,
        },
      ],
    };
    if (c.format === 'dc+sd-jwt') {
      return { format: 'dc+sd-jwt', vct: c.vct, ...common };
    }
    return { format: 'mso_mdoc', doctype: c.doctype, ...common };
  }

  authorizationServerMetadata() {
    const iss = this.iss;
    return {
      issuer: iss,
      authorization_endpoint: `${iss}/authorize`,
      pushed_authorization_request_endpoint: `${iss}/par`,
      require_pushed_authorization_requests: true,
      token_endpoint: `${iss}/token`,
      jwks_uri: `${iss}/jwks.json`,
      response_types_supported: ['code'],
      response_modes_supported: ['query'],
      grant_types_supported: [
        'authorization_code',
        'urn:ietf:params:oauth:grant-type:pre-authorized_code',
        'refresh_token',
      ],
      code_challenge_methods_supported: ['S256'],
      token_endpoint_auth_methods_supported: ['attest_jwt_client_auth'],
      token_endpoint_auth_signing_alg_values_supported: ['ES256'],
      dpop_signing_alg_values_supported: ['ES256'],
      authorization_response_iss_parameter_supported: true,
      scopes_supported: CREDENTIAL_CONFIGS.map((c) => c.scope),
    };
  }
}
