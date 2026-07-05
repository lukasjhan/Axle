---
title: 파사드 API
---

# 파사드 API

모든 것은 조립된 `Wallet` 하나로 접근합니다.

## `wallet.credentials` — `CredentialsService`

| 멤버 | 설명 |
|---|---|
| `list(filter)` | 저장된 크리덴셜을 파싱된 포맷 무관 뷰로 |
| `get(id)` / `delete(id)` | 단건 조회 / 삭제 |
| `match(dcqlJson)` | DCQL 쿼리를 만족하는 크리덴셜 |
| `status(id)` | 폐기 상태 (Token Status List) |
| `changes` | `Added` / `Updated` / `Removed` 스트림 |

## `wallet.issuance` — `IssuanceService`

| 멤버 | 설명 |
|---|---|
| `resolveOffer(uri)` | 오퍼 딥링크 / QR / JSON 파싱 |
| `start(request)` | 발급 세션 시작 |
| `resumeDeferred(id)` | deferred 크리덴셜 폴링 |
| `reissue(id)` | 저장된 refresh 토큰으로 갱신 |

세션: `IssuanceState` = `Preparing → AuthorizationRequired | TxCodeRequired → Processing → Completed | Failed`. `completeAuthorization(redirect)` / `submitTxCode(code)`로 재개.

## `wallet.presentation` — `PresentationService`

| 멤버 | 설명 |
|---|---|
| `start(requestUri)` | 원격(URL/QR) 제시 |
| `startDcApi(requestObject, origin)` | Digital Credentials API (브라우저) |

세션: `PresentationState` = `ResolvingRequest → RequestResolved → Submitting → Completed | Declined | Failed`. `respond(selection)` / `decline()`로 재개.

## `wallet.proximity` — `ProximityService`

| 멤버 | 설명 |
|---|---|
| `present(transport)` | 당신의 transport 위에서 ISO 18013-5 device retrieval |

세션: `ProximityState` = `GeneratingEngagement → EngagementReady → RequestReceived → Submitting → Completed | Declined | Failed`. `respond(selection)` / `decline()`로 재개.

## `wallet.transactions` — `TransactionLog`

주입된 store 위에서 `history()` · `query(type, relyingPartyId, since, until)`.

## 에러

도메인별 타입: `WalletError.Issuance`(Kotlin) / `IssuanceError`(Swift), `…Presentation` / `PresentationError`, `…Proximity` / `ProximityError` — invalid request, verifier/reader not trusted, selection incomplete, response rejected 등.
