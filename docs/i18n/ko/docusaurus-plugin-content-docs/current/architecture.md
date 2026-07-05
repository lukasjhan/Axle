---
sidebar_position: 2
title: 아키텍처
---

# 아키텍처

## 포트 & 어댑터

SDK 코어는 **플랫폼 의존성이 없는** 순수 로직입니다 — 일반 JVM/Linux(및 Linux Swift)에서 실행·단위테스트됩니다. 플랫폼별 요소는 모두 호스트가 구현해 생성 시점에 주입하는 **포트**입니다.

```
   ┌──────────────────────────── 당신의 앱 (UI) ────────────────────────────┐
   │                                                                        │
   │   Wallet.create(config, ports)                                         │
   │        │                                                               │
   │        ▼                                                               │
   │   ┌────────────────── Wallet 파사드 ──────────────────┐                 │
   │   │ credentials · issuance · presentation · proximity │                │
   │   └───────────────────────┬───────────────────────────┘                │
   │        코어 모듈 (순수)     │  cbor · sdjwt · mdoc · openid4vci/vp ·      │
   │                           │  trust · statuslist · credential-store ·   │
   │                           │  proximity · txlog                         │
   │                           ▼                                            │
   │   포트 (당신이 주입) ▸ SecureArea · StorageDriver · HttpTransport ·     │
   │                        Rng · WalletClock · ProximityTransport ·        │
   │                        TransactionLogStore · WalletAttestationProvider │
   └────────────────────────────────────────────────────────────────────────┘
```

## 포트들

| 포트 | 책임 | 대표 어댑터 |
|---|---|---|
| `SecureArea` | 키 생성·서명·공개키 보관 | Android Keystore / iOS Secure Enclave (테스트는 소프트웨어) |
| `StorageDriver` | 컬렉션/키로 바이트 영속 | 암호화 파일 / DataStore / Keychain |
| `HttpTransport` | 리다이렉트 제어가 있는 HTTP 실행 | OkHttp / URLSession |
| `Rng` | 랜덤 바이트 | `SecureRandom` (기본 제공) |
| `WalletClock` | 현재 시각 | 시스템 시계 (기본 제공) |
| `ProximityTransport` | BLE/NFC 양방향 채널 | GATT 페리페럴 (대면 전용) |
| `TransactionLogStore` | 추가 전용 감사 영속 | 암호화 저장소 (기본 인메모리) |
| `WalletAttestationProvider` | Wallet Provider 연동(WUA) | 백엔드 클라이언트 |

SDK가 크리덴셜·키·발급·제시 라이프사이클을 **소유**하고, 호스트는 위의 얇은 기능만 제공합니다 — DI 프레임워크 없이 생성자 주입뿐입니다.

## 모듈

각 관심사를 별도 모듈로 분리해 독립 테스트·재사용합니다:

`cbor`(CBOR/COSE) · `sdjwt`(SD-JWT VC, JOSE) · `mdoc`(ISO 18013-5) · `openid4vci` · `openid4vp` ·
`trust`(X.509 PKIX) · `statuslist`(Token Status List) · `credential-store` · `proximity`(18013-5 세션) ·
`txlog`(감사) · `wallet`(이들을 조립하는 파사드).

## 상태머신으로서의 세션

발급·제시·근접은 **일시정지 가능한 상태머신**입니다. 상호작용 지점(브라우저 인가, `tx_code`, 동의)에서 멈췄다가 앱이 콜백하면 재개합니다 — Kotlin은 `StateFlow`, Swift는 `AsyncStream`.

```
start(...) → Processing → [일시정지: AuthorizationRequired / TxCodeRequired / RequestResolved]
           → [앱 재개] → Submitting → Completed | Failed | Declined
```
