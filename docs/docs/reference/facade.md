---
title: Facade API
---

# Facade API

Everything is reached through an assembled `Wallet`.

## `wallet.credentials` — `CredentialsService`

| Member | Description |
|---|---|
| `list(filter)` | Stored credentials as a parsed, format-agnostic view (`CredentialFilter.All` by default) |
| `get(id)` / `delete(id)` | Single fetch / remove |
| `export(id)` | Raw serialized credential for backup/inspection (SD-JWT compact string, or base64url mdoc); null if unknown or not issued |
| `match(dcqlJson)` | Which credentials satisfy a DCQL query |
| `status(id)` | Revocation status (Token Status List) |
| `changes` | Stream of `Added` / `Updated` / `Removed` |

## `wallet.issuance` — `IssuanceService`

| Member | Description |
|---|---|
| `resolveOffer(uri)` | Parse an offer deep link / QR / JSON |
| `start(request)` | Begin an issuance session |
| `resumeDeferred(id)` | Poll a deferred credential |
| `reissue(id)` | Renew via the stored refresh token |

Session: `IssuanceState` = `Preparing → AuthorizationRequired | TxCodeRequired → Processing →
Completed | Deferred | Failed`. Resume with `completeAuthorization(redirect)` / `submitTxCode(code)`.
The three terminal states are `Completed`, `Deferred` (issuer not ready — resume with `resumeDeferred`),
and `Failed`.

## `wallet.presentation` — `PresentationService`

| Member | Description |
|---|---|
| `start(requestUri)` | Remote (URL/QR) presentation |
| `startDcApi(requestObject, origin)` | Digital Credentials API (browser) |

Session: `PresentationState` = `ResolvingRequest → RequestResolved → Submitting → Completed |
Declined | Failed`. Resume with `respond(selection)` / `decline()`.

## `wallet.proximity` — `ProximityService`

| Member | Description |
|---|---|
| `present(transport)` | ISO 18013-5 device retrieval over your transport |

Session: `ProximityState` = `GeneratingEngagement → EngagementReady → RequestReceived → Submitting →
Completed | Declined | Failed`. Resume with `respond(selection)` / `decline()`.

## `wallet.reader` — `ProximityReaderService`

The ISO 18013-5 **reader** role (Read mDL): request documents from another wallet and verify the returned
`DeviceResponse`.

| Member | Description |
|---|---|
| `read(transport, engagement, documents, handoverNdef?, handoverRequestNdef?)` | Drive the reader half over your transport; returns `List<VerifiedDocument>` (each with `deviceAuthenticated`) |

Issuer trust uses `TrustConfig.issuerAnchorsDer`; the wallet signs its requests with
`WalletConfig.readerAuth` when set. See [Proximity](../guides/proximity#reading-another-wallet-reader-side).

## `wallet.transactions` — `TransactionLog`

`history()` · `query(type, relyingPartyId, since, until)` over the injected store.

## Errors

Typed per domain: `WalletError.Issuance` (Kotlin) / `IssuanceError` (Swift), `…Presentation` /
`PresentationError`, `…Proximity` / `ProximityError` — invalid request, verifier/reader not trusted,
selection incomplete, response rejected, etc.
