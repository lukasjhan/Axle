import { Logger } from '@nestjs/common';
import type { IntegrityResult } from '../platform-verifier';

const logger = new Logger('PlayIntegrity');

/**
 * Loads the Google service account from the `GOOGLE_SERVICE_ACCOUNT_JSON` secret string (not a file path),
 * so the image stays config-less. The value must be valid JSON with `private_key`'s newlines intact — store
 * it single-quoted with compact JSON (`jq -c`). Returns `undefined` to fall back to Application Default
 * Credentials.
 */
function serviceAccountCredentials(): Record<string, unknown> | undefined {
  const saJson = process.env.GOOGLE_SERVICE_ACCOUNT_JSON;
  return saJson ? (JSON.parse(saJson) as Record<string, unknown>) : undefined;
}

/**
 * Decodes an Android Play Integrity token via Google and checks the verdicts + nonce. Requires
 * `google-auth-library` (an optional dependency) and a service account (the `GOOGLE_SERVICE_ACCOUNT_JSON`
 * secret, or Application Default Credentials as a fallback).
 * Reference: https://developer.android.com/google/play/integrity/standard#decrypt-verify
 */
/**
 * Nonce equality tolerant of base64 vs base64url and padding: Play Integrity returns the nonce it received
 * re-encoded as standard, padded base64, so a raw string compare against our base64url challenge always fails.
 */
function nonceMatches(tokenNonce: string | undefined, challenge: string): boolean {
  if (!tokenNonce) return false;
  const bytes = (s: string): Buffer => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  const a = bytes(tokenNonce);
  return a.length > 0 && a.equals(bytes(challenge));
}

export async function verifyPlayIntegrity(
  packageName: string,
  token: string,
  challenge: string,
): Promise<IntegrityResult> {
  try {
    const moduleName = 'google-auth-library'; // computed specifier: optional dep, resolved only at runtime
    const { GoogleAuth } = (await import(moduleName)) as any;
    const credentials = serviceAccountCredentials();
    const auth = new GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/playintegrity'],
      ...(credentials ? { credentials } : {}),
    });
    const accessToken = await (await auth.getClient()).getAccessToken();

    const res = await fetch(`https://playintegrity.googleapis.com/v1/${packageName}:decodeIntegrityToken`, {
      method: 'POST',
      headers: { authorization: `Bearer ${accessToken.token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ integrity_token: token }),
    });
    if (!res.ok) return { trusted: false, platform: 'android', reason: `Play Integrity decode failed: ${res.status}` };

    const verdict = ((await res.json()) as any)?.tokenPayloadExternal;
    // Play Integrity echoes the nonce re-encoded as standard, padded base64 (`…==`); the challenge we issued is
    // base64url without padding. Same bytes, different string — so compare the decoded bytes, not the strings.
    if (!nonceMatches(verdict?.requestDetails?.nonce, challenge)) {
      return { trusted: false, platform: 'android', reason: 'Play Integrity nonce mismatch' };
    }
    const appVerdict = verdict?.appIntegrity?.appRecognitionVerdict;
    const appRecognized = appVerdict === 'PLAY_RECOGNIZED';
    const deviceOk: boolean = (verdict?.deviceIntegrity?.deviceRecognitionVerdict ?? []).includes('MEETS_DEVICE_INTEGRITY');
    if (!appRecognized || !deviceOk) {
      const detail = `app=${appVerdict ?? 'none'}, device ok=${deviceOk}`;
      // Dev/sandbox: the token decoded and its nonce matched (so it's a genuine Play Integrity response), but
      // the trust verdict is weak — typically a sideloaded UNRECOGNIZED_VERSION build. Log and allow through.
      if (process.env.DEV_INTEGRITY_BYPASS === 'true') {
        logger.warn(`DEV_INTEGRITY_BYPASS: accepting weak Play Integrity verdict (${detail})`);
        return { trusted: true, platform: 'android' };
      }
      return { trusted: false, platform: 'android', reason: `Play Integrity verdict failed (${detail})` };
    }
    return { trusted: true, platform: 'android' };
  } catch (e) {
    logger.error(`Play Integrity verification error: ${(e as Error).message}`);
    return { trusted: false, platform: 'android', reason: 'verification error (google-auth-library installed + credentials configured?)' };
  }
}
