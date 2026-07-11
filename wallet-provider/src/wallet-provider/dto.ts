import type { JWK } from 'jose';

/** POST /wallet-instances — register a wallet instance after a device-integrity check. */
export class RegisterInstanceDto {
  instanceKey!: JWK; // the wallet instance public key (bound into the WUA cnf)
  integrityToken!: string; // Play Integrity / App Attest token (dev: `dev-integrity:<nonce>`)
  nonce!: string; // from GET /nonce
}

/** POST /wallet-attestation — obtain a WUA; `pop` proves possession of the instance key. */
export class WalletAttestationDto {
  instanceId!: string;
  clientId?: string; // WUA subject; defaults to instanceId
  pop!: string; // JWT signed by the instance key: { aud: WP issuer, nonce, iat }
}

/** POST /key-attestation — attest credential proof keys; `nonce` is the issuer's c_nonce. */
export class KeyAttestationDto {
  attestedKeys!: JWK[];
  nonce?: string;
  keyAttestations?: string[]; // base64 android-keystore-x5c chains (one per key) → verified to assert the storage level
}
