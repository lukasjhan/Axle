import { Injectable, Logger } from '@nestjs/common';
import {
  devIntegrity,
  type IntegrityResult,
  type KeyAttestationVerdict,
  type PlatformVerifier,
} from '../platform-verifier';
import { verifyAppAttest } from './app-attest';

/**
 * iOS verification via Apple App Attest. At registration the client sends an App Attest attestation for a
 * freshly generated key, bound to the wallet-provider nonce; we verify the attestation certificate chain
 * (rooted in the Apple App Attest CA), the nonce, the key identifier, and that it came from our app
 * (`APPLE_APP_ID` = "<TEAM_ID>.<BUNDLE_ID>"). The dev bypass (`dev-integrity:<nonce>`) is still honoured when
 * `DEV_INTEGRITY_BYPASS=true`, matching the Android side and side-loaded builds.
 */
@Injectable()
export class IosVerifier implements PlatformVerifier {
  readonly platform = 'ios' as const;
  private readonly logger = new Logger(IosVerifier.name);

  async verifyIntegrity(integrityToken: string | undefined, challenge: string): Promise<IntegrityResult> {
    const dev = devIntegrity(integrityToken, challenge, 'ios');
    if (dev) return dev;
    if (!integrityToken) return { trusted: false, platform: 'ios', reason: 'missing integrity token' };
    if (!integrityToken.startsWith('appattest:')) {
      return { trusted: false, platform: 'ios', reason: 'unrecognized integrity token' };
    }

    let parsed: { keyId?: string; attestation?: string };
    try {
      parsed = JSON.parse(Buffer.from(integrityToken.slice('appattest:'.length), 'base64').toString('utf8'));
    } catch {
      return { trusted: false, platform: 'ios', reason: 'malformed App Attest token' };
    }
    if (!parsed.keyId || !parsed.attestation) {
      return { trusted: false, platform: 'ios', reason: 'App Attest token missing keyId/attestation' };
    }

    const appId = process.env.APPLE_APP_ID ?? 'P3A48743C4.com.hopae.axle.wallet';
    const result = await verifyAppAttest(Buffer.from(parsed.attestation, 'base64'), parsed.keyId, challenge, appId);
    if (!result.trusted) this.logger.warn(`App Attest rejected: ${result.reason}`);
    return result;
  }

  async verifyKeyAttestation(): Promise<KeyAttestationVerdict> {
    // iOS credential keys live in the Secure Enclave but expose no X.509 attestation chain to verify here.
    // App Attest assertions over the proof keys would raise this to high; without them we assert moderate.
    return { level: 'iso_18045_moderate' };
  }
}
