/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Canonical public origin shown in the curl commands (e.g. https://trust.hopae.dev). */
  readonly VITE_SITE_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
