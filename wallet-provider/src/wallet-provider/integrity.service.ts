import { Injectable, Logger } from '@nestjs/common';

export interface IntegrityResult {
  trusted: boolean;
  platform: 'android' | 'ios' | 'dev';
  reason?: string;
}

/**
 * Platform integrity attestation verifier (Android Play Integrity / iOS App Attest).
 * Pluggable: real verifiers need Google/Apple cloud credentials, so the default here is a DEV
 * stub that accepts a `dev-integrity:<nonce>` token. Swap for a production verifier via DI.
 */
@Injectable()
export class IntegrityService {
  private readonly logger = new Logger(IntegrityService.name);

  async verify(integrityToken: string | undefined, nonce: string): Promise<IntegrityResult> {
    // DEV stub — production: verify Play Integrity JWT / App Attest assertion against the nonce.
    if (integrityToken === `dev-integrity:${nonce}`) {
      return { trusted: true, platform: 'dev' };
    }
    this.logger.warn('integrity token not recognized (dev stub expects `dev-integrity:<nonce>`)');
    return { trusted: false, platform: 'dev', reason: 'unrecognized integrity token' };
  }
}
