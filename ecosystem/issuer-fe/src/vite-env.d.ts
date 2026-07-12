/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Issuer backend origin (e.g. https://issuer.hopae.dev). The FE calls `${VITE_ISSUER_BE_URL}/eudi-issuer/...`. */
  readonly VITE_ISSUER_BE_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
