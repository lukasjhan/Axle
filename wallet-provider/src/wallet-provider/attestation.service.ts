import { Injectable } from '@nestjs/common';
import * as jose from 'jose';
import { KeystoreService } from './keystore.service';

/** Issues the two artifacts a HAIP wallet needs from its provider: WUA + key attestation. */
@Injectable()
export class AttestationService {
  constructor(private readonly keystore: KeystoreService) {}

  /**
   * Wallet Unit Attestation = OAuth 2.0 client attestation
   * (draft-ietf-oauth-attestation-based-client-auth). Binds the wallet instance key via `cnf.jwk`;
   * the wallet later signs a matching `oauth-client-attestation-pop+jwt` to authenticate to issuers.
   */
  async issueWalletAttestation(instanceKey: jose.JWK, clientId: string): Promise<string> {
    return new jose.SignJWT({
      cnf: { jwk: instanceKey },
      wallet_name: 'Hopae EUDI Wallet',
      wallet_link: 'https://wallet.hopae.dev',
      aal: 'https://trust-list.eu/aal/high',
    })
      .setProtectedHeader({ typ: 'oauth-client-attestation+jwt', alg: 'ES256', x5c: this.keystore.x5c })
      .setIssuer(this.keystore.issuer)
      .setSubject(clientId)
      .setIssuedAt()
      .setExpirationTime('24h')
      .sign(this.keystore.signingKey);
  }

  /**
   * Key attestation (OpenID4VCI §8.2.1.1) — attests the credential proof keys live in a secure area.
   * `nonce` binds it to the issuer's c_nonce (passed through, not a WP-issued nonce).
   */
  async issueKeyAttestation(attestedKeys: jose.JWK[], nonce?: string): Promise<string> {
    const payload: jose.JWTPayload = {
      attested_keys: attestedKeys,
      key_storage: ['iso_18045_high'],
      user_authentication: ['iso_18045_high'],
    };
    if (nonce) payload.nonce = nonce;
    return new jose.SignJWT(payload)
      .setProtectedHeader({ typ: 'keyattestation+jwt', alg: 'ES256', x5c: this.keystore.x5c })
      .setIssuer(this.keystore.issuer)
      .setIssuedAt()
      .setExpirationTime('24h')
      .sign(this.keystore.signingKey);
  }
}
