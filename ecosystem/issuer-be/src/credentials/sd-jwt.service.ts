import { Injectable } from '@nestjs/common';
import { SDJwtInstance } from '@sd-jwt/core';
import { generateSalt, digest, ES256 } from '@sd-jwt/crypto-nodejs';
import type { DisclosureFrame } from '@sd-jwt/types';
import { KeystoreService, type SignerType } from '../crypto/keystore.service';

/**
 * SD-JWT VC signing primitive (IETF SD-JWT VC / RFC 9901). Signs with the Issuer DSC as ES256, header
 * `typ: dc+sd-jwt` (HAIP) and `x5c` = [leaf DSC] so verifiers resolve the issuer via the published Trusted
 * List (trust anchor excluded from x5c per HAIP §6.1.1). The payload/disclosureFrame are assembled by the
 * caller (credential configs); everything not listed in the disclosure frame stays in the base JWT.
 */
@Injectable()
export class SdJwtService {
  constructor(private readonly keystore: KeystoreService) {}

  async issue<T extends Record<string, unknown>>(
    payload: T,
    disclosureFrame: DisclosureFrame<T>,
    signerType: SignerType = 'pid',
  ): Promise<string> {
    const signer = this.keystore.getSigner(signerType);
    const es256 = await ES256.getSigner(signer.privateJwk);
    const sdjwt = new SDJwtInstance({
      saltGenerator: generateSalt,
      hashAlg: 'sha-256',
      hasher: digest,
      signAlg: 'ES256',
      signer: es256,
    });
    return sdjwt.issue(payload, disclosureFrame, {
      header: { typ: 'dc+sd-jwt', x5c: signer.x5c },
    });
  }
}
