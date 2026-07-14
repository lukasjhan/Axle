# Axle

**Axle is a headless, from-scratch SDK for building EU Digital Identity (EUDI) wallets** — issuing, storing,
and presenting digital credentials under **eIDAS 2.0** (ARF · HAIP). Embed it in your own app and you own the
UI; the SDK owns the protocols, cryptography, and trust. The reference wallet built with it is **Axle Wallet**.

It ships as **two native implementations — Kotlin and Swift** — that share only an API contract, with a pure
core that builds and tests on plain Linux. New to EUDI? Start with **[Concepts](docs/docs/concepts.mdx)**.

## Why this SDK

- **Headless (UI-less).** A B2B library your app embeds — no screens, no opinions about your UX. You wire
  it to your product; you keep full control of the user experience.
- **Dependency-injected, no framework.** The core is pure and platform-agnostic. Every platform capability
  — secure-key hardware, storage, HTTP, Bluetooth/NFC — is a small **port** you supply an **adapter** for
  (plain constructor injection). Swap any piece; test the core on Linux.
- **Batteries included, not required.** Production **Android adapters** live in `android/` — use them as-is,
  or as a reference for your own. A full **Android demo wallet** (Jetpack Compose) is in `demo/`.
- **Full scratch, standards-first.** The EU reference wallet is an *interop target, not a dependency*. Every
  layer — CBOR/COSE, SD-JWT VC, ISO mdoc, OpenID4VCI/VP, X.509 trust, Token Status List — is implemented
  in-house against the source specifications (see **[SPEC-MATRIX.md](SPEC-MATRIX.md)** and the
  [specifications reference](docs/docs/reference/specs.md)).

Everything is reached through one assembled `Wallet` facade — `credentials`, `issuance`, `presentation`,
`proximity`, `reader`, `transactions`.

## Try the hosted sandbox

A live end-to-end EUDI ecosystem you can point the wallet at — issue a PID, present it to a verifier, all
against real trusted-list-anchored trust:

| Service | URL | Role |
|---|---|---|
| **PID Issuer** | https://pid-issuer.vercel.app/ | Issues PID (SD-JWT VC & mdoc) and mDL — OpenID4VCI |
| **Verifier** | https://eudi-verifier.vercel.app/ | Requests & verifies presentations — OpenID4VP + DC API |
| **RP Registrar** | https://demo-registrar.vercel.app/ | Registers relying parties; issues WRPAC/WRPRC (ETSI TS 119 475) |
| **Trusted List** | https://trusted-list.vercel.app/ | Scheme Operator — JAdES-signed trust lists (ETSI TS 119 602) |

The demo wallet in `demo/` is pre-wired to these. Build it (`cd demo && ./gradlew :app:assembleDebug`) or
see **[demo/RELEASE.md](demo/RELEASE.md)** for signed AAB + Play internal-testing distribution.

## Repository layout

| Path | What |
|---|---|
| `kotlin/` | Kotlin SDK (pure JVM, Gradle multi-module) — the reference core |
| `swift/` | Swift package mirroring the Kotlin modules 1:1 (no Apple-framework imports; Linux-buildable) |
| `android/` | Android platform-adapter presets (`com.hopae.eudi.android:core`/`proximity`/`dcapi`/`attestation`) — Keystore/StrongBox SecureArea, file storage, OkHttp, BLE + NFC transports, DC API glue, Play Integrity attestation |
| `demo/` | Android wallet app (Compose) consuming `kotlin/` + `android/` — the reference assembly; release guide in [`demo/RELEASE.md`](demo/RELEASE.md) |
| `ios/` | iOS platform plan (SecureEnclave adapter + DC API) — not yet implemented |
| `docs/` | Docusaurus developer docs (English + 한국어) — [see below](#documentation) |
| `ecosystem/` | The reference sandbox services (issuer, verifier, trusted list) — [see below](#the-reference-ecosystem) |
| `wallet-provider/` | NestJS Wallet Provider backend — Wallet Unit Attestation (WUA) + key attestation + Play Integrity |
| `vectors/` | Shared golden test vectors consumed by both test suites |

**Core rule:** everything under `kotlin/` and `swift/` builds and tests on plain Linux. Platform features
(secure hardware, storage, BLE, DC API) live strictly behind ports.

## Architecture: ports & adapters

The core is pure; the host injects capabilities. Assembling a wallet is: pick adapters, set config, call
`Wallet.create(config, ports)`.

```
        your app (UI)                     ← you build this
             │
        ┌────▼─────────────────────────┐
        │   Wallet (facade)            │  credentials · issuance · presentation
        │                              │  proximity · reader · transactions
        └────┬─────────────────────────┘
   pure core │  OpenID4VCI/VP · SD-JWT VC · ISO mdoc · X.509 trust · CBOR/COSE
        ┌────▼─────────────────────────┐
        │   Ports (SPI)                │  SecureArea · StorageDriver · HttpTransport
        │                              │  ProximityTransport · WalletAttestationProvider
        └────┬─────────────────────────┘
   adapters  │  ← android/ presets (or your own)
        Keystore · files · OkHttp · BLE/NFC · Play Integrity
```

The [`android/`](android/) adapters are a ready-made preset; [`demo/app/.../DemoWallet.kt`](demo/app/src/main/kotlin/com/hopae/eudi/demo/DemoWallet.kt)
is the canonical "assemble from adapters + config" example. Full walkthrough in
[`docs/` → Getting Started](docs/docs/getting-started.mdx) and [Architecture](docs/docs/architecture.md).

## Quick start

```kotlin
// Assemble once from platform adapters + config (Android preset shown).
val wallet = Wallet.create(
    config = WalletConfig(trust = TrustConfig(issuerAnchorsDer, readerAnchorsDer, registrarAnchorsDer)),
    ports  = WalletPorts(
        secureAreas = listOf(AndroidKeystoreSecureArea()),   // your SecureArea adapter
        storage     = FileStorageDriver(dir),                // your StorageDriver adapter
        http        = OkHttpTransport(),                     // your HttpTransport adapter
    ),
)

wallet.issuance.resolveOffer(offerUri)   // OpenID4VCI — resolve → start session → store credential
wallet.presentation.start(requestUri)    // OpenID4VP  — resolve → select credentials → submit
wallet.proximity.present(transport)      // ISO 18013-5 — present in person over BLE/NFC
wallet.credentials.list()                // stored credentials (+ DCQL match, status)
wallet.transactions.history()            // audit log
```

Swap `AndroidKeystoreSecureArea` / `FileStorageDriver` / `OkHttpTransport` for your own adapters (or the
`testkit` software ones) to run the same core anywhere. Full walkthrough — Kotlin + Swift — in
[Getting Started](docs/docs/getting-started.mdx).

## Modules

Each concern is a separate module (Kotlin name / Swift target), tested in isolation.

| Module | Purpose | Key types |
|---|---|---|
| `cbor` / `CborCose` | CBOR (RFC 8949) + COSE primitives | `Cbor`, `CborEncoder`, `cose/CoseSign1`, `CoseKey`, `EcPublicKey`, `Ecdsa`, `Der` |
| `sdjwt` / `SdJwt` | SD-JWT VC + JOSE (JWS/JWE/JWK) | `SdJwt`, `SdJwtIssuer/Holder/Verifier`, `SdJwtVcVerifier`, `Jws`, `Jwe`, `SecureAreaJwsSigner` |
| `mdoc` / `MDoc` | ISO 18013-5 mdoc / mDL | `IssuerSigned`/`MobileSecurityObject`, `DeviceRequest`, `DeviceResponse`, `MdocPresenter`, `MdocReader`, `ReaderAuthSigner`, `Hpke` |
| `openid4vci` / `OpenID4VCI` | OpenID4VCI issuance | `Openid4VciClient`, `CredentialOffer`, `CredentialIssuerMetadata`, `DpopProver`, `KeyAttestationSource` |
| `openid4vp` / `OpenID4VP` | OpenID4VP presentation + DCQL | `Openid4VpClient`, `DcqlQuery`, `DcqlMatchResult`, `TransactionData`, `RegistrationInfo` |
| `trust` / `Trust` | X.509 PKIX trust + WRPRC | `X509ChainValidator`, `X5cMdocIssuerTrust/ReaderTrust`, `X509RequestVerifier`, `WRPRCVerifier`, `RegistrarApiClient` |
| `statuslist` / `StatusList` | IETF Token Status List (revocation) | `StatusListClient`, `CwtStatusListClient`, `CredentialStatus` |
| `credential-store` / `CredentialStore` | Persisted credential store | `CredentialStore`, `CredentialEnvelope`, `EnvelopeCodec` (deterministic CBOR) |
| `proximity` / `Proximity` | ISO 18013-5 engagement + NFC handover | `DeviceEngagement`, `ProximitySessionTranscript`, `SessionMessages`, `MdocNfcEngagement`, `Tnep` |
| `txlog` / `TransactionLog` | Audit log (ARF/GDPR) | `TransactionLog`, `TransactionLogStore` (port), `TransactionLogEntry`, `RelyingParty` |
| `wallet-api` / `WalletAPI` | Port SPI + shared types | `spi/` ports (`SecureArea`, `StorageDriver`, `HttpTransport`, `ProximityTransport`, `WalletAttestationProvider`), `Types`, `SecureAreaCoseSigner` |
| `wallet` / `Wallet` | **The facade + composition root** | `Wallet`, `WalletConfig`, `WalletPorts`, `CredentialsService`, `IssuanceService`, `PresentationService`, `ProximityService`, `ProximityReaderService` |
| `testkit` / `WalletTestKit` | Test doubles + adapter contracts | `SoftwareSecureArea`, `InMemoryStorageDriver`, `SecureAreaContract`, `StorageDriverContract` |

## Build & test

```bash
# Kotlin — pure JVM
cd kotlin && ./gradlew test

# Swift — on this Linux host, point clang at a GCC dir that has libstdc++-dev:
cd swift && swift test \
  -Xcc --gcc-install-dir=/usr/lib/gcc/x86_64-linux-gnu/11 \
  -Xcxx --gcc-install-dir=/usr/lib/gcc/x86_64-linux-gnu/11 \
  -Xlinker -L/usr/lib/gcc/x86_64-linux-gnu/11
# (CI images `swift:6.x` need no extra flags.)

# Android demo → APK
cd demo && ./gradlew :app:assembleDebug     # app/build/outputs/apk/debug/app-debug.apk
```

## Documentation

Full developer documentation (guides + API reference, Kotlin + Swift examples, English + 한국어) lives in
`docs/` as a Docusaurus site:

- **[Concepts](docs/docs/concepts.mdx)** — EUDI/eIDAS vocabulary for developers new to the domain
- **[Architecture](docs/docs/architecture.md)** · **[Getting Started](docs/docs/getting-started.mdx)** — assemble the SDK from ports & adapters
- **Guides** — [Issuance](docs/docs/guides/issuance.mdx) · [Presentation](docs/docs/guides/presentation.mdx) · [Digital Credentials API](docs/docs/guides/dc-api.md) · [Proximity](docs/docs/guides/proximity.mdx) · [Trust & Audit](docs/docs/guides/trust-and-audit.mdx)
- **Reference** — [Facade](docs/docs/reference/facade.md) · [Ports](docs/docs/reference/ports.mdx) · [Specifications](docs/docs/reference/specs.md)

```bash
cd docs && npm install
npm start                 # dev server (English)
npm start -- --locale ko  # dev server (한국어)
npm run build             # static build of both locales
```

## The reference ecosystem

A complete EUDI sandbox — every counterpart the wallet talks to — lives in this repo (except the Registrar,
a separate project at [github.com/hopae-official/registrar](https://github.com/hopae-official/registrar);
sandbox at [demo-registrar.vercel.app](https://demo-registrar.vercel.app/)):

| Service | Path | Role |
|---|---|---|
| **Issuer backend** | [`ecosystem/issuer-be`](ecosystem/issuer-be/README.md) | OpenID4VCI 1.0 + HAIP — issues PID (SD-JWT VC & mdoc) and mDL |
| **Issuer frontend** | [`ecosystem/issuer-fe`](ecosystem/issuer-fe/README.md) | Issuance-consent screen (authorization-code flow) |
| **Verifier backend** | [`ecosystem/verifier-be`](ecosystem/verifier-be/README.md) | OpenID4VP 1.0 + HAIP — builds & verifies presentations (QR + DC API) |
| **Verifier frontend** | [`ecosystem/verifier-fe`](ecosystem/verifier-fe/README.md) | Relying-party UI (request QR / DC API, show result) |
| **Trusted List** | [`ecosystem/trusted-list`](ecosystem/trusted-list/README.md) | Scheme Operator — JAdES-signed trust lists + ecosystem CAs ([KEYS.md](ecosystem/KEYS.md)) |
| **Wallet Provider** | [`wallet-provider`](wallet-provider/README.md) | Wallet Unit Attestation (WUA) + key attestation + Play Integrity ([PLAY-INTEGRITY.md](wallet-provider/PLAY-INTEGRITY.md)) |

See [`ecosystem/README.md`](ecosystem/README.md) for the trust model overview.

## Status

Reference / sandbox implementation for eIDAS 2.0 EUDI interoperability. The Kotlin and Swift cores and the
Android adapters are functional and tested (CI runs both suites); iOS adapters are planned. The hosted
services above are a **non-production sandbox**.

## License

Licensed under the **Apache License 2.0** — see [LICENSE](LICENSE).
