import { Injectable, Logger } from '@nestjs/common';
import * as jose from 'jose';
import { KeystoreService } from './keystore.service';
import { verifyAndroidKeyAttestation } from './android-key-attestation';

/** Issues the two artifacts a HAIP wallet needs from its provider: WUA + key attestation. */
@Injectable()
export class AttestationService {
  private readonly logger = new Logger(AttestationService.name);
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
  async issueKeyAttestation(attestedKeys: jose.JWK[], nonce?: string, keyAttestations?: string[]): Promise<string> {
    const level = await this.resolveKeyStorageLevel(keyAttestations, nonce);
    const payload: jose.JWTPayload = {
      attested_keys: attestedKeys,
      key_storage: [level],
      user_authentication: [level],
    };
    if (nonce) payload.nonce = nonce;
    return new jose.SignJWT(payload)
      .setProtectedHeader({ typ: 'keyattestation+jwt', alg: 'ES256', x5c: this.keystore.x5c })
      .setIssuer(this.keystore.issuer)
      .setIssuedAt()
      .setExpirationTime('24h')
      .sign(this.keystore.signingKey);
  }

  /**
   * The `key_storage` level to assert, *derived from evidence* rather than on faith: only when every
   * provided Android Key Attestation chain verifies (roots in a trusted Google root, in TEE/StrongBox, with
   * the challenge = the issuer nonce) is `iso_18045_high` claimed. A tampered/invalid chain is rejected; no
   * chain (e.g. a software secure area) yields the lower `iso_18045_moderate`.
   */
  private async resolveKeyStorageLevel(keyAttestations: string[] | undefined, nonce?: string): Promise<string> {
    if (!keyAttestations || keyAttestations.length === 0) {
      this.logger.warn('key attestation issued without a hardware chain — asserting iso_18045_moderate');
      return 'iso_18045_moderate';
    }
    const challenge = new TextEncoder().encode(nonce ?? '');
    let allHardware = true;
    for (const b64 of keyAttestations) {
      const verdict = await verifyAndroidKeyAttestation(new Uint8Array(Buffer.from(b64, 'base64')), challenge);
      if (!verdict.verified) throw new Error(`key attestation chain rejected: ${verdict.reason}`);
      if (nonce && !verdict.challengeMatches) throw new Error('key attestation challenge does not match the issuer nonce');
      if (verdict.securityLevel === 'software') allHardware = false;
    }
    return allHardware ? 'iso_18045_high' : 'iso_18045_moderate';
  }
}
