# WRPRC delivery: what the wallet does with `verifier_info`

How a Wallet-Relying Party Registration Certificate (WRPRC) reaches the wallet during a presentation,
and exactly what the wallet must do in each case — **both artifacts present** vs **registrar dataset
only** (fall back to the Registrar API).

Companion to [`TODO.md`](TODO.md) *"Next session — decide where the WRPRC arrives"* and
[`SPEC-MATRIX.md`](SPEC-MATRIX.md). Scope: the **remote OpenID4VP** flow (HAIP); the ISO/IEC 18013-5
proximity parallel is in [§7](#7-isoiec-18013-5-proximity-parallel).

---

## 1. TL;DR

A conformant RP puts **Registrar-provided data into the OpenID4VP `verifier_info` array** of the signed
Request Object (ETSI TS 119 472-2 §6.3). Two kinds of element:

| `verifier_info[].format` | Carries | Required? | Trust level |
|---|---|---|---|
| `"registrar_dataset"` | RP's registered fields as **plain JSON** | **Always** (REQ-RO-02) | RP-self-declared — only the request signature (WRPAC) covers it; **not** Registrar-attested |
| `"registration_cert"` | The **WRPRC** (`rc-wrp+jwt` / CWT), base64url | **Only if the RP holds one** (REQ-RO-13) | **Registrar-sealed** — JAdES B-B, chains to the registrar CA. Authoritative, offline-verifiable |

The decision the wallet makes is driven by **which of these is present** and by **whether the User opted
to verify** (ARF Topic 44, `RPRC_16`):

- **cert present** → verify the cert, bind it to the WRPAC, done **offline** — no Registrar call
  (`RPRC_17`; the whole point of "by value" in `RPRC_19`).
- **cert absent, dataset only** → if the User opted in, **call the Registrar's TS5 API** to obtain the
  same information *Registrar-signed* (`RPRC_18`). The dataset alone is not proof of registration.

> ⚠️ Naming collision: this SDK already has a type called `VerifierInfo`
> (`kotlin/openid4vp/.../vp/Request.kt`, `swift/.../OpenID4VP`) — that is the **internal trust-result**
> (clientId, scheme, x5c, trusted). It is **not** the OpenID4VP `verifier_info` request parameter
> described here. The request parameter is **not parsed yet** (see [§8](#8-mapping-to-this-sdk)).

---

## 2. What the RP sends (ETSI TS 119 472-2 §6.3)

```jsonc
// Signed Request Object (JWS) body. client_id MUST use the x509_hash prefix (OIDFVP-HAIP-COMMON-REQ-01);
// the request is signed by the RP's WRPAC (access certificate), leaf in the x5c header.
{
  "client_id": "x509_hash:Uvo3HtuIxuhC92rShpgqcT3YXwrqRxWEviRiA0OZszk",
  "response_type": "vp_token",
  "verifier_info": [                                    // MANDATORY — REQ-RO-01
    {
      "format": "registrar_dataset",                   // MANDATORY element — REQ-RO-02/04
      // data = plain JSON, self-declared by the RP (integrity only via the request signature)
      "data": {
        "identifier":            [ { "type": "…", "identifier": "VATLU-12345678" } ], // REQ-RO-06
        "srvDescription":        [ { "lang": "en", "content": "Awesome Service" } ],  // REQ-RO-07
        "registryURI":           "https://registrar.example/registrar",              // REQ-RO-08 ← API base
        "intendedUseIdentifier": "use-42",                                           // REQ-RO-09
        "purpose":               [ { "lang": "en", "content": "Age check" } ],       // REQ-RO-10
        "policyURI":             "https://rp.example/privacy",                        // REQ-RO-11
        "credential":            [ /* Credential objects: format/meta/claim */ ]     // REQ-RO-12 (MAY)
      }
    },
    {
      "format": "registration_cert",                   // ONLY if the RP has a WRPRC — REQ-RO-13/15
      "data": "eyJ0eXAiOiJyYy13cnAr…"                  // base64url( serialized WRPRC ) — REQ-RO-16
    }
  ]
}
```

- Neither element carries `credential_ids` (REQ-RO-03 / REQ-RO-14).
- `data` in the cert element is **base64url of the serialized WRPRC** — decode it to get the
  `rc-wrp+jwt` (ETSI TS 119 475), then verify per [§6](#6-verifying-the-wrprc-this-sdk).

### Presence matrix (recap)

| dataset | cert | Valid? | Wallet path |
|---|---|---|---|
| ✅ | ✅ | ✅ | [§4](#4-both-present) — use the cert (authoritative); dataset is UI/log convenience |
| ✅ | ✖ | ✅ | [§5](#5-dataset-only--registrar-api-ts5) — Registrar API fallback if User opts in |
| ✖ | ✅ | ❌ | dataset is mandatory — reject as malformed |
| ✖ | ✖ | ❌ | `verifier_info` mandatory — reject as malformed |

---

## 3. Preconditions common to both paths

Before looking at `verifier_info` at all, the request itself must already be trusted:

1. **WRPAC / request-object trust** — verify the Request Object JWS: chain the `x5c` leaf (the WRPAC)
   to a trusted **reader/registrar anchor**, verify the signature, and enforce `client_id` =
   `x509_hash:base64url(SHA-256(leaf DER))`. This SDK does it in `X509RequestVerifier`. The **WRPAC leaf
   (DER)** it validates is the anchor everything below binds to.
2. **User's verify preference** (`RPRC_16`) — after showing the request (or as a global setting), the
   wallet offers the User the choice to verify the Registrar-registered information. Everything in §4/§5
   that reaches out or blocks on registration data is **gated on this opt-in**; the name/identifier/
   purpose needed for the base consent screen come from the request regardless.

---

## 4. Both present

The `registration_cert` is **Registrar-sealed and self-contained**, so it wins. No network needed.

1. **Decode** `verifier_info[format=="registration_cert"].data` (base64url) → the `rc-wrp+jwt`.
2. **Verify the WRPRC** per [§6](#6-verifying-the-wrprc-this-sdk): JAdES signature to the registrar CA,
   `typ`/`alg`/`crit`, validity, and **bind to the WRPAC** (`sub == WRPAC.organizationIdentifier`,
   `GEN-5.1.1-02`). On failure → `RPRC_17`: do **not** trust it; when asking approval (`RPA_07`) notify the
   User "could not obtain the information registered about the entity."
3. **Status-list check** — feed the WRPRC `status` claim to the Token Status List client; a revoked WRPRC
   is refused.
4. **Attribute-scope check** (`RPRC_21`) — compare every attribute requested in the presentation (DCQL)
   against the credentials/claims the WRPRC declares as registered. Requested-but-not-registered attributes
   are surfaced to the User at approval.
5. **Consent surfacing** — show `purpose` (intended use), entitlements, privacy-policy link, and — if
   intermediated — both the intermediary (from the WRPAC / `act`) and the final RP (`sub`).
6. **`registrar_dataset` role here** — do **not** treat it as an independent source of truth: it is only
   RP-self-declared. Use it for the **transaction log** (`DASH_03`: RP identifier, `registryURI`, DPA and
   data-deletion contacts) and as a display fallback for fields the cert doesn't carry. **On any conflict,
   the cert wins.** No Registrar call is made in this path.

---

## 5. Dataset only → Registrar API (TS5)

No cert. The dataset is self-declared, so it is **not** proof of registration. If the User opted in
(`RPRC_16`), the wallet obtains the authoritative, **Registrar-signed** information online (`RPRC_18`), from
the **`registryURI` in the dataset**. API = EUDI Wallet **TS5** (*Common formats and API for RP
Registration information*).

**Base URL** = `registrar_dataset.data.registryURI` (e.g. `https://registrar.example/registrar`).
All responses are `application/jwt` — a **JWS-signed** payload (`SignedWRP`); verify the signature against
the Registrar's key/trust before using anything.

### 5.1 Fetch the registered RP record — for display + attribute list

```
GET {registryURI}/wrp/{identifier}
        identifier = registrar_dataset.data.identifier   // the RP's unique id
Accept: application/jwt
→ 200  JWS( WalletRelyingParty )
```

Verify the JWS, then read the fields the UI and checks need:

| Need | Field in `WalletRelyingParty` |
|---|---|
| Display name | `legalName`, `tradeName` |
| Service description | `srvDescription` (localized) |
| Intended use / purpose | `intendedUse[]` → `purpose`, `privacyPolicy`, `createdAt`/`revokedAt` |
| **Registered attributes** (for `RPRC_21`) | `intendedUse[].credentials[]` → `format`, `meta`, `claims[].path` |
| DPA (for reporting) | `supervisoryAuthority` → `name`, `country`, `email`, `phone`, `formURI` |
| Data-deletion contact | `supportURI[]` |
| Entitlements | `entitlements[]` |
| Intermediary chain | `usesIntermediary[]`, `isIntermediary` |

> Pick the `intendedUse[]` entry whose `intendedUseIdentifier` equals
> `registrar_dataset.data.intendedUseIdentifier`. Treat it as revoked/invalid if `revokedAt` has passed.

### 5.2 Verify requested attributes are registered — targeted boolean check

Instead of (or in addition to) diffing §5.1's `credentials[]` locally, call the dedicated check endpoint
**once per requested attribute** (or per credential):

```
GET {registryURI}/wrp/check-intended-use
        rpidentifier          = <RP identifier>          (required)
        intendeduseidentifier = <intended-use id>        (optional)
        credentialformat      = dc+sd-jwt | mso_mdoc      (optional)
        claimpath             = <e.g. "age_over_18">      (optional)
        credentialmeta        = <credential type meta>    (optional)
        policyurl             = <privacy policy URL>      (optional)
Accept: application/jwt
→ 200  JWS( { "isRegistered": true|false, "details": "…"? } )
```

`isRegistered=false` ⇒ that attribute is **not** covered by the RP's registration ⇒ warn the User at
approval (`RPRC_21`).

### 5.3 Failure / opt-out handling

- **User did not opt in** (`RPRC_16` = no): make **no** Registrar call. The wallet MAY still render the
  self-declared `registrar_dataset` fields for the consent screen, but must not present them as
  Registrar-verified.
- **Registrar unreachable, or signature/`isRegistered` verification fails** (`RPRC_18`): when asking
  approval (`RPA_07`), notify the User that it "could not obtain the information registered about the
  Relying Party." The transaction can still proceed on the User's informed decision.
- **Privacy**: this is an online call keyed by RP identifier; make it only on opt-in, and prefer §5.2's
  narrow boolean over pulling the whole record when only an attribute check is needed.

---

## 6. Verifying the WRPRC (this SDK)

`WRPRCVerifier` (kotlin `trust/`, swift `Sources/Trust/`) already implements the cert checks used by §4:

- Header: `typ == "rc-wrp+jwt"`, `alg == "ES256"`, `crit` only `{sigT, b64}`, `b64 != false`
  (JAdES over RFC 7515/7797).
- Signature: `x5c` chained to the **registrar CA** (`X509ChainValidator` built from
  `TrustConfig.registrarAnchorsDer`), then ECDSA-verified; optional `x5t#S256` thumbprint match.
- Payload: validity (`exp` optional per TS 119 475 Table 10), `sub` present.
- **Binding** `GEN-5.1.1-02` / `RPRC_04`: the presented WRPAC's `organizationIdentifier` (X.509 OID
  `2.5.4.97`, from the WRPAC leaf DER handed in by the request verifier) must equal the entity that signed
  the request. **Direct** request → that is the RP itself, so `WRPAC.orgId == sub`. **Intermediated** request
  → the request is signed by the intermediary, so `WRPAC.orgId == intermediary.sub` (== `act.sub`); `sub`
  stays the **final** RP for display only. The mediated RP has no WRPAC of its own — only the intermediary does.
- Extracts `entitlements` (≥1), `purpose`, `intermediary` (with `act.sub == intermediary.sub`,
  `GEN-5.2.4-09`), and returns the raw `status` for the Token Status List check.

Result → `VerifiedWRPRC { subject, entitlements, purpose, intermediary, claims, status }`. The intermediary
(`sub` + `sname`) and final RP (`subject`) both surface to the app via `VerifierRegistration`
(`intermediarySub` / `intermediaryName` / `subject`). Covered by `WRPRCTest.intermediatedWRPRC` (+ the
negative `intermediatedWRPRCRejectsFinalRpWrpac`) on both Kotlin and Swift.

---

## 7. ISO/IEC 18013-5 proximity parallel

Same two artifacts, carried in `ItemsRequest.requestInfo` (ETSI TS 119 472-2, `ISO/IEC 18013-REQ-05…11`):

```cddl
RequestInfo = {
  ? "euWrprc"          : bstr,                 ; serialized WRPRC — only if the RP has one (REQ-06..08)
    "euWrpRegistrarInfo": EUWrpRegistrarInfo   ; MANDATORY — same fields as registrar_dataset (REQ-09..11)
}
```

Wallet logic is identical: `euWrprc` present → verify + bind (WRPAC here is the reader-auth cert in
`x5chain` of `readerAuth`); absent → fall back to the Registrar API using
`euWrpRegistrarInfo.registryURI` + `identifier`. Note the spec CDDL comment shows `eUWrprc` but the
normative label is **`euWrprc`**.

---

## 8. Mapping to this SDK

**Chokepoint**: `X509RequestVerifier.verifyRequestObject(...)` — it already validates the WRPAC leaf and
enforces `x509_hash`. That is where the WRPRC path hooks in, because the **validated WRPAC leaf DER** is in
hand exactly there and `WRPRCVerifier.verify(wrprc, wrpacLeafDer)` needs it.

Open work (tracked in `TODO.md` "wire `WRPRCVerifier` into the live flow"):

1. **Parse the OpenID4VP `verifier_info` array** in `openid4vp/.../vp/Request.kt` (and swift): pull the
   `registrar_dataset` element (always) and the `registration_cert` element (optional). Give it a name that
   doesn't collide with the existing `VerifierInfo` trust-result type (e.g. `RegistrarVerifierInfo`).
2. **Invoke `WRPRCVerifier`** at the `X509RequestVerifier` chokepoint when `registration_cert` is present,
   passing the WRPAC leaf DER; surface `entitlements`/`purpose`/`intermediary` to the consent screen.
3. **Status-list**: feed `VerifiedWRPRC.status` to the existing `StatusListClient` — refuse a revoked WRPRC.
4. **Registrar API client (TS5)** for the dataset-only path (§5): `GET {registryURI}/wrp/{identifier}` and
   `GET {registryURI}/wrp/check-intended-use`, JWS-verify responses. Gate on the `RPRC_16` opt-in.
5. **Attribute-scope check** (`RPRC_21`) against the WRPRC's / Registrar record's registered credentials.

---

## 9. Normative references

- **ETSI TS 119 472-2** v1.2.1 §6.3 — `verifier_info` transport, `format` values, `requestInfo` extension
  (`OIDFVP-HAIP-COMMON-REQ-RO-01…18`, `ISO/IEC 18013-REQ-02…11`).
- **ETSI TS 119 475** v1.2.1 — WRPRC content/format (`rc-wrp+jwt`), binding `GEN-5.1.1-02`, entitlements.
- **EUDI ARF** Topic 44 — `RPRC_16` (User opt-in), `RPRC_17` (verify cert), `RPRC_18` (Registrar fallback),
  `RPRC_19/19a` (include by value), `RPRC_20/20a` (transport = 472-2), `RPRC_21` (attribute scope).
- **EUDI Wallet TS5** — Registrar API: `GET /wrp`, `GET /wrp/{identifier}`, `GET /wrp/check-intended-use`;
  `WalletRelyingParty` schema; `application/jwt` (JWS) responses.
- **OpenID4VP 1.0** §5.11 (Verifier Info), §5.9.3 (`x509_hash` Client Identifier Prefix).

> Status: 472-2 v1.2.1 (2026-03) is current, but ARF `RPRC_20` notes the transport will be "amended by a
> CIR in preparation" — re-verify the `format` strings and endpoint shapes when that CIR publishes.
