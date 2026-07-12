import type { MdocContext } from '@lukas.j.han/mdoc';

// COSE/crypto context for @lukas.j.han/mdoc, ISSUANCE only. The library delegates hashing and the COSE_Sign1
// (MSO) signature to this context; we back both with WebCrypto (ECDSA P-256 / SHA-256). MAC0, ephemeral-key
// agreement and X.509 chain verification are presentation/verification concerns and are not wired here.
const EC_ALGO = { name: 'ECDSA', namedCurve: 'P-256' } as const;
const SIGN_ALGO = { name: 'ECDSA', hash: 'SHA-256' } as const;

const notForIssuance = (name: string) => () => {
  throw new Error(`mdocContext.${name} is not implemented (issuance-only context)`);
};

export const mdocContext: MdocContext = {
  crypto: {
    digest: async ({ digestAlgorithm, bytes }) => {
      const out = await crypto.subtle.digest(digestAlgorithm, new Uint8Array(bytes));
      return new Uint8Array(out);
    },
    random: (length: number) => crypto.getRandomValues(new Uint8Array(length)),
    calculateEphemeralMacKey: notForIssuance('crypto.calculateEphemeralMacKey'),
  },
  cose: {
    mac0: {
      sign: notForIssuance('cose.mac0.sign'),
      verify: notForIssuance('cose.mac0.verify'),
    },
    sign1: {
      sign: async ({ key, sign1 }) => {
        const cryptoKey = await crypto.subtle.importKey('jwk', key.jwk as JsonWebKey, EC_ALGO, false, ['sign']);
        const sig = await crypto.subtle.sign(SIGN_ALGO, cryptoKey, new Uint8Array(sign1.toBeSigned));
        return new Uint8Array(sig);
      },
      verify: notForIssuance('cose.sign1.verify'),
    },
  },
  x509: {
    getIssuerNameField: notForIssuance('x509.getIssuerNameField'),
    getPublicKey: notForIssuance('x509.getPublicKey'),
    verifyCertificateChain: notForIssuance('x509.verifyCertificateChain'),
    getCertificateData: notForIssuance('x509.getCertificateData'),
  },
} as MdocContext;
