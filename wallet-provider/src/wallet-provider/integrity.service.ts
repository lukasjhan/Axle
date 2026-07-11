import { Injectable, Logger } from '@nestjs/common';

export interface IntegrityResult {
  trusted: boolean;
  platform: 'android' | 'ios' | 'dev';
  reason?: string;
}

/**
 * Platform integrity attestation verifier (Android Play Integrity / iOS App Attest).
 *
 * The DEV stub accepts a `dev-integrity:<nonce>` token so local development and the demo's fallback path
 * work without cloud credentials. Real **Android Play Integrity** verification is enabled by setting
 * `PLAY_INTEGRITY_PACKAGE_NAME` and providing Application Default Credentials (a service account with the
 * Play Integrity API enabled) — it decodes the token via Google and checks the app/device verdicts and nonce.
 */
@Injectable()
export class IntegrityService {
  private readonly logger = new Logger(IntegrityService.name);

  async verify(integrityToken: string | undefined, nonce: string): Promise<IntegrityResult> {
    if (!integrityToken) return { trusted: false, platform: 'dev', reason: 'missing integrity token' };

    // DEV stub: the token the reference wallet emits when a real Play Integrity verdict is unavailable.
    if (integrityToken === `dev-integrity:${nonce}`) {
      return { trusted: true, platform: 'dev' };
    }

    // Real Android Play Integrity — only when configured (else the token is unrecognized).
    const packageName = process.env.PLAY_INTEGRITY_PACKAGE_NAME;
    if (packageName) {
      return this.verifyPlayIntegrity(packageName, integrityToken, nonce);
    }

    this.logger.warn('integrity token not recognized (no PLAY_INTEGRITY_PACKAGE_NAME; dev stub expects `dev-integrity:<nonce>`)');
    return { trusted: false, platform: 'dev', reason: 'unrecognized integrity token' };
  }

  /**
   * Decodes an Android Play Integrity token via Google and checks the verdicts + nonce. Requires
   * `google-auth-library` (an optional dependency) and Application Default Credentials.
   * Reference: https://developer.android.com/google/play/integrity/standard#decrypt-verify
   */
  private async verifyPlayIntegrity(packageName: string, token: string, nonce: string): Promise<IntegrityResult> {
    try {
      const moduleName = 'google-auth-library'; // computed specifier: optional dep, resolved only at runtime
      const { GoogleAuth } = (await import(moduleName)) as any;
      const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/playintegrity'] });
      const accessToken = await (await auth.getClient()).getAccessToken();

      const res = await fetch(`https://playintegrity.googleapis.com/v1/${packageName}:decodeIntegrityToken`, {
        method: 'POST',
        headers: { authorization: `Bearer ${accessToken.token}`, 'content-type': 'application/json' },
        body: JSON.stringify({ integrity_token: token }),
      });
      if (!res.ok) return { trusted: false, platform: 'android', reason: `Play Integrity decode failed: ${res.status}` };

      const verdict = ((await res.json()) as any)?.tokenPayloadExternal;
      if (verdict?.requestDetails?.nonce !== nonce) {
        return { trusted: false, platform: 'android', reason: 'Play Integrity nonce mismatch' };
      }
      const appRecognized = verdict?.appIntegrity?.appRecognitionVerdict === 'PLAY_RECOGNIZED';
      const deviceOk: boolean = (verdict?.deviceIntegrity?.deviceRecognitionVerdict ?? []).includes('MEETS_DEVICE_INTEGRITY');
      if (!appRecognized || !deviceOk) {
        return { trusted: false, platform: 'android', reason: 'Play Integrity verdict failed (app/device)' };
      }
      return { trusted: true, platform: 'android' };
    } catch (e) {
      this.logger.error(`Play Integrity verification error: ${(e as Error).message}`);
      return { trusted: false, platform: 'android', reason: 'verification error (google-auth-library installed + ADC configured?)' };
    }
  }
}
