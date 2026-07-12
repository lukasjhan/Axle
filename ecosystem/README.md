# Hopae EUDI Sandbox — Ecosystem

A standards-conformant, self-operated sandbox for the EU Digital Identity Wallet (EUDI). Every trust
relationship is anchored in X.509 certificates and published as ETSI-standard, JAdES-signed **Trusted Lists**
— so wallets, issuers and verifiers can establish trust the same way they would in the real eIDAS ecosystem.

## Live — Trusted List portal

**https://trusted-list.vercel.app**

The Scheme Operator (**Hopae**) publishes the Trusted Lists of the entities in the sandbox. Each list is a
[ETSI TS 119 602](https://www.etsi.org/standards) *List of Trusted Entities* (LoTE), signed as
[ETSI TS 119 182-1](https://www.etsi.org/standards) **JAdES** (Baseline-B). Verifiers download the signed
list for a service type — compact JWS or JAdES JSON — or fetch it with `curl`.

| List | Trust anchor it publishes | Credentials / use | Standard |
| --- | --- | --- | --- |
| **Wallet Providers** | WP CA that wallet-unit attestations (WUAs) chain to | Axle Wallet | ETSI TS 119 602 Annex E |
| **PID Issuers** | PID Issuer CA | PID — SD-JWT VC + mdoc | EUDI ARF (PID Providers) |
| **Attestation Issuers** | Attestation Issuer CA | mDL — mdoc (ISO/IEC 18013-5) | EUDI ARF ((Q)EAA Providers) |
| **Registrar** | Registrar CA relying-party access certs chain to | RP registration | EUDI ARF (Registration) |

Every list is signed by the Hopae **Scheme Operator** key (self-signed root; per ETSI TS 119 602 §6.8 the
signer's `C` = Scheme Territory = `EU` and `O` = Scheme operator = `Hopae`). Signatures are ES256 with the
claimed signing time (`sigT`) critical and the signing certificate bound both by value (`x5c`) and by
reference (`x5t#S256`).

## Trust model

```
Scheme Operator (Hopae, C=EU)  ──signs──▶  Trusted Lists (JAdES)
                                              │  each list publishes a trust anchor:
   Wallet Providers list  ──▶ WP CA           ├─▶ wallet-unit attestations (WUAs) chain to WP CA
   PID Issuers list       ──▶ PID Issuer CA   ├─▶ PID (SD-JWT VC / mdoc) chain to PID Issuer CA
   Attestation list       ──▶ Attestation CA  ├─▶ mDL (mdoc) chains to Attestation CA
   Registrar list         ──▶ Registrar CA    └─▶ relying-party access certs chain to Registrar CA
```

A verifier trusts a credential by: fetching the relevant signed list → checking the JAdES signature against
the Scheme Operator → then checking the credential's certificate chains to a CA on that list.

## Components

- [`trusted-list/`](./trusted-list) — the Scheme Operator: builds + JAdES-signs the Trusted Lists and serves
  them as a static site (Vite + shadcn/ui, deployed to Vercel). See its README for how to add a list, mint a
  CA, regenerate and deploy.

## Roadmap

- [x] **P1** Scheme Operator + Trusted Lists (wallet providers, PID issuers, attestation issuers, registrar)
- [ ] **P2** PID Issuer backend (SD-JWT VC + mdoc), issuing under the PID Issuer CA
- [ ] **P3** Attestation / mDL issuer (IACA → document signers), under the Attestation CA
- [ ] **P4** Verifier (relying party) that consumes these lists
- [ ] **P5** Registrar backend

## Security

The Scheme Operator signing key and the issuer CA private keys are held offline
(`trusted-list/secrets/`, gitignored — move to KMS/HSM for anything beyond the sandbox). Lists are re-issued
at least every 6 months (Annex E `nextUpdate`).
