# EUDI Wallet Provider — backend

ARF **Wallet Provider**. Attests that a wallet instance runs on a genuine, uncompromised device, then issues
the two attestations a HAIP wallet needs from its provider:

- **Wallet Unit Attestation (WUA)** — an OAuth 2.0 Attestation-Based Client Authentication JWT
  (`draft-ietf-oauth-attestation-based-client-auth`, `typ: oauth-client-attestation+jwt`). It binds the wallet
  instance key via `cnf.jwk`; the wallet later signs a matching `oauth-client-attestation-pop+jwt` to
  authenticate as a client to the Issuer.
- **Key Attestation** — OpenID4VCI 1.0 §8.2.1.1 (`typ: keyattestation+jwt`). It attests that a batch of
  credential-proof keys live in the device's secure area, at a `key_storage` assurance **derived from hardware
  evidence** (not asserted on faith).

Registration integrity is **pluggable per platform** — Android **Play Integrity** and Android **Key
Attestation** are implemented; iOS **App Attest** is stubbed pending the reference iOS holder. The provider also
handles instance **registration** and **revocation**, and publishes a **Token Status List** so relying parties
can check WUA revocation without a per-instance call. The SDK's `WalletAttestationProvider` port
(`kotlin/wallet-api`, `swift/WalletAPI`) binds to this backend to complete HAIP client authentication end to end.

NestJS 11 + Fastify, mirrors the sibling `issuer-be` / `verifier-be` (pino, Prometheus, terminus, Drizzle +
Postgres, Redis, env-loaded signing keys). Attestation JWTs are signed with `jose`; Android attestation crypto
uses `@peculiar/asn1-android` / `asn1-x509` / `x509`; Play Integrity decode uses `google-auth-library`.
TypeScript, `pnpm`. Sandbox — not a production Wallet Provider.

Everything is served under the global prefix **`/wp`** (e.g. `GET /wp/nonce`); listens on port **3200**. Play
Integrity setup (Google Cloud project, service account, client/backend wiring, reading the verdict, and getting
`PLAY_RECOGNIZED` via Play Console internal testing) is documented in [`PLAY-INTEGRITY.md`](PLAY-INTEGRITY.md).

## How it fits

1. **Register** — the wallet gets a `nonce` (`GET /wp/nonce`), obtains a platform integrity token bound to it
   (Play Integrity on Android; the `dev-integrity:<nonce>` placeholder when a real verdict is unavailable), and
   `POST`s `{instanceKey, integrityToken, nonce, platform}` to `/wp/wallet-instances`. On a passing integrity
   check the provider records the instance and returns a stable `instanceId` (UUID).
2. **Get a WUA** — the wallet `POST`s `{instanceId, pop}` to `/wp/wallet-attestation`, where `pop` is a fresh
   JWT signed by the instance key (`aud` = WP issuer, single-use `nonce`). The provider returns the WUA, which
   the wallet presents as **client authentication** at the Issuer's PAR/token endpoints.
3. **Get Key Attestations** — per issuance, the wallet `POST`s the credential-proof public keys (plus the
   Android Key Attestation chains) with the Issuer's `c_nonce` to `/wp/key-attestation`; the provider verifies
   the chains and returns a Key Attestation proving the keys are hardware-bound.
4. **Trust** — the Issuer (and Verifier) trust these attestations because the WP signer certificate chains to
   the **WP CA published on the Trusted List** (`ecosystem/trusted-list`, entity `wallet-providers.json`). The
   attestation JWTs carry `x5c = [signer cert]` (the leaf only); the CA is distributed separately as the trust
   anchor — served here at `/.well-known/wallet-provider-ca.pem` for local dev, and pinned on the Trusted List
   in the ecosystem.
5. **Revoke** — an admin revokes an instance; its bit flips to INVALID in the Token Status List that every WUA
   references, so issuers/RPs see the revocation on their next list fetch.

## Endpoints

> All paths carry the global prefix **`/wp`**. Health probes and the Prometheus scrape sit under the same prefix.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/nonce` | Single-use, short-lived (5 min) challenge nonce for registration and attestation PoP. Redis-backed when `REDIS_URL` is set (atomic `GETDEL`), else in-memory |
| POST | `/wallet-instances` | Register an instance: `{instanceKey(JWK), integrityToken, nonce, platform?}` → device-integrity check → `{instanceId}` (UUID). `platform` ∈ `android`\|`ios` (default `android`) |
| POST | `/wallet-attestation` | Issue a WUA: `{instanceId, clientId?, pop}` → `{wallet_attestation}`. `pop` = JWT signed by the instance key (`aud` = WP issuer, single-use `nonce`, `iat`); `clientId` defaults to `instanceId`. Rejected for an unknown/revoked instance |
| POST | `/key-attestation` | Issue a Key Attestation: `{attestedKeys(JWK[]), nonce?, keyAttestations?, platform?}` → `{key_attestation}`. `nonce` = the Issuer's `c_nonce` (passed through); `keyAttestations` = base64 Android Key Attestation x5c chains, one per key |
| POST | `/wallet-instances/:id/revoke` | **Admin** (`x-api-key`): soft-revoke an instance — no further WUA, and its status-list bit flips to INVALID → `{revoked}` |
| GET | `/wallet-instances/:id/status` | Instance status `{instanceId, revoked, createdAt, revokedAt}` — an issuer/RP's per-instance revocation check |
| GET | `/status-lists/:id` | Token Status List Token (`application/statuslist+jwt`) referenced by each WUA's `status.status_list{idx, uri}`. RPs decode the DEFLATE/zlib bit array to check revocation without a per-instance call. Only id `1` is published |
| GET | `/.well-known/jwks.json` | WP signing public key (JWKS) — issuers may verify WUA signatures via JWKS instead of `x5c` |
| GET | `/.well-known/wallet-provider-ca.pem` | WP CA certificate (`application/x-pem-file`) — a relying wallet/issuer installs it as a trust anchor |
| GET | `/health` · `/live` · `/ready` | terminus probes — `/health` liveness alias (empty check), `/live` heap check (512 MB), `/ready` gates on a Postgres ping |
| GET | `/metrics` | Prometheus scrape — default Node metrics + an `http_request_duration_seconds{method,route,status_code}` histogram (health/metrics excluded) |

## Attestations, trust & security

- **WUA** (`AttestationService.issueWalletAttestation`) — `typ: oauth-client-attestation+jwt`, `alg: ES256`,
  `x5c: [signer cert]`. Payload binds the instance key via `cnf.jwk`, carries wallet metadata (`wallet_name`,
  `wallet_link`, `aal`) and a `status.status_list` reference, `iss` = `WP_ISSUER`, `sub` = `clientId`, 24 h TTL.
  Issued only after the instance-key **PoP** verifies (signature over the instance's `cnf` key, `aud` = WP
  issuer) and its `nonce` is consumed single-use.
- **Key Attestation** (`AttestationService.issueKeyAttestation`) — `typ: keyattestation+jwt`, `alg: ES256`,
  `x5c: [signer cert]`. Payload carries `attested_keys`, and `key_storage` / `user_authentication` set to the
  evidence-derived assurance level, with the Issuer's `c_nonce` echoed as `nonce`, 24 h TTL.
- **Trust chain** — every WUA / Key Attestation / status-list token carries `x5c = [signer cert]` (the signing
  leaf only, by convention). Relying issuers install the **WP CA** as the trust anchor and chain the signer to
  it. The signer certificate is an **ETSI TS 119 412-6** Wallet Provider sign/seal cert: EN 319 412-3
  legal-person DN, `digitalSignature` key usage, AKI/SKI + Authority Information Access (`caIssuers`), and a
  QCStatements extension carrying the QcType **`id-etsi-qct-wal`** (`0.4.0.194126.1.2`, Annex A).
- **Keystore** (`src/attestation/keystore.service.ts`) — production loads a persistent signer key + signer cert
  + CA cert from PEM env vars (`WP_SIGNER_PRIVATE_KEY` / `WP_SIGNER_CERT` / `WP_CA_CERT`) so the trust anchor is
  **stable across restarts and replicas** (mint once with `tools/gen-keystore.mjs`). If unset, an ephemeral
  self-signed CA + signer are generated per process — fine locally, but WUAs then won't verify across
  restarts/replicas.
- **Platform integrity** (`src/platform/`) — a `PlatformVerifier` per OS behind a registry, dispatched by the
  request's `platform`:
  - **Android registration**: `verifyPlayIntegrity` decodes the token via Google `decodeIntegrityToken`
    (`google-auth-library` + a service account), checks the nonce (anti-replay, base64/base64url-tolerant), and
    requires `PLAY_RECOGNIZED` + `MEETS_DEVICE_INTEGRITY`. Active when `PLAY_INTEGRITY_PACKAGE_NAME` is set.
  - **Android key attestation**: each provided chain is verified (validity, unrevoked, roots pinned to Google,
    TEE/StrongBox, challenge = the Issuer nonce) → `iso_18045_high`; a tampered/invalid/revoked chain is
    rejected; no chain yields `iso_18045_moderate`.
  - **iOS**: App Attest is not yet implemented (rejects non-dev tokens); the seam is registered so real App
    Attest slots in without touching the controller.
  - **Dev bypass**: `DEV_INTEGRITY_BYPASS=true` accepts the `dev-integrity:<nonce>` placeholder and lets a weak
    real Play Integrity verdict (e.g. a sideloaded `UNRECOGNIZED_VERSION` build) through with a log. OFF by
    default; **never set in production**.
- **Admin auth** — revoke is guarded by `AdminApiKeyGuard` (`x-api-key` = `ADMIN_API_KEY`, constant-time
  compare). Unset ⇒ the guard allows through and warns (dev only).

## Run locally

Postgres is required (`DATABASE_URL`). Redis is optional (in-memory fallback for a single replica).

```bash
cp .env.example .env            # PORT, STAGE, DATABASE_URL, WP_ISSUER (+ optional Play Integrity vars)
# local Postgres:
docker run -d --name wp-pg -p 5432:5432 \
  -e POSTGRES_USER=wp -e POSTGRES_PASSWORD=wp -e POSTGRES_DB=wallet_provider postgres:16

pnpm install
pnpm db:generate                # only when the Drizzle schema changes → drizzle/ SQL migrations
pnpm build && pnpm migrate      # apply migrations (node dist/migrate)
pnpm start                      # or: pnpm start:dev (watch) / pnpm start:prod (node dist/main)

node test/wp-flow.mjs           # full flow e2e against a running server
```

Tools: `node tools/gen-keystore.mjs` mints the persistent WP keystore (CA + signer) for the `WP_SIGNER_*` /
`WP_CA_CERT` secrets; `node tools/decode-integrity.mjs "<token>"` decodes a Play Integrity token by hand (see
[`PLAY-INTEGRITY.md`](PLAY-INTEGRITY.md)). `env.validation.ts` (class-validator) checks the required vars on
boot and refuses to start if any is missing.

## Configuration

Config-less by design — everything is injected via environment (no config file in the image).

| Var | Required | Purpose |
| --- | --- | --- |
| `STAGE` | yes | Deployment stage label (e.g. `dev`) |
| `PORT` | yes | Listen port (`.env.example`: `3200`) |
| `DATABASE_URL` | yes | Postgres connection string (postgres.js + Drizzle) |
| `WP_ISSUER` | yes | WP issuer/base URL — the `iss` of issued JWTs and the instance-PoP audience. **Include the `/wp` prefix** (e.g. `http://localhost:3200/wp`) |
| `WP_SIGNER_PRIVATE_KEY` | — | Persistent signer private key (PEM, `\n`-escaped ok). All three `WP_*` together ⇒ a stable trust anchor across restarts/replicas |
| `WP_SIGNER_CERT` | — | Persistent signer certificate (PEM) |
| `WP_CA_CERT` | — | WP CA certificate (PEM). Unset (any of the three) ⇒ ephemeral per-process dev keys |
| `LOG_LEVEL` | — | pino level (default `debug` non-prod, `info` prod) |
| `REDIS_URL` | — | Shared nonce store — required for multi-replica; unset ⇒ in-memory (single-replica / local dev) |
| `ADMIN_API_KEY` | — | Admin key for the revoke endpoint, sent as `x-api-key`. Unset ⇒ revoke is unprotected (dev only) |
| `DEV_INTEGRITY_BYPASS` | — | Accept `dev-integrity:<nonce>` and pass weak Play verdicts through. OFF by default; **never in prod** |
| `PLAY_INTEGRITY_PACKAGE_NAME` | — | Android app package to enable real Play Integrity (e.g. `com.hopae.axle.wallet`) |
| `ANDROID_ATTESTATION_ROOTS` | — | Override the Android Key Attestation trust anchors (PEM bundle); default = pinned Google roots |
| `ANDROID_ATTESTATION_STATUS_URL` | — | Override the Android attestation revocation status URL (default = Google's `attestation/status`) |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | — | Service-account key as a compact JSON **string** (not a file path) for Play Integrity decode; omit ⇒ Application Default Credentials |

## Deploy

Container is built by the `Dockerfile` — `node:24-alpine` multi-stage, non-root (`wp` uid 1001), config-less
(runtime env only), `EXPOSE 3200`, `CMD ["node", "dist/main"]`. Run `node dist/migrate` as a migration
Job / init-container so the schema is applied before serving. Scrape with `prometheus.io/port: "3200"`,
`prometheus.io/path: "/wp/metrics"`. The k8s manifests live in the separate infra repo (as with `issuer-be` /
`verifier-be`). Inject `DATABASE_URL`, `WP_ISSUER` (with the prefix), the `WP_SIGNER_*` / `WP_CA_CERT`
keystore, `REDIS_URL`, `ADMIN_API_KEY`, and (for real Play Integrity) `PLAY_INTEGRITY_PACKAGE_NAME` +
`GOOGLE_SERVICE_ACCOUNT_JSON` — via AWS Secrets Manager → External Secrets Operator — and leave
`DEV_INTEGRITY_BYPASS` unset. The dev deployment is reachable at **https://dev.api.hopae.com/wp**.

## Standards

OAuth 2.0 Attestation-Based Client Authentication (`draft-ietf-oauth-attestation-based-client-auth`) ·
OpenID4VCI 1.0 §8.2.1.1 (key attestation) · IETF Token Status List (`draft-ietf-oauth-status-list`) ·
Android Key Attestation · Google Play Integrity · ETSI TS 119 412-6 (`id-etsi-qct-wal` Wallet Provider
sign/seal cert) · EN 319 412-1/-2/-3/-5. Sandbox — not a production Wallet Provider.
