---
id: specs
title: 명세
sidebar_position: 99
---

# 명세

이 SDK가 구현하는 정확한 원본 명세들을 표준화 기구별로 묶은 목록입니다. 각 항목은 프로젝트가 추적하는
제목과 버전, **SDK가 그것을 어디에 사용하는지**에 대한 한 줄 설명, 그리고 (로컬 사본이 아닌) **공식
공개 출처**로의 링크를 제공합니다.

조항 수준의, 버전이 고정된 구현 범위 — 각 명세의 어떤 버전이 구현되었는지, 무엇이 부분적인지, 알려진
공백은 무엇인지 — 는 **저장소 루트의 `SPEC-MATRIX.md`**를 참고하세요(이 문서는 본 docs 사이트 외부에
있어 여기서 링크되지 않습니다).

접근 안내: **ISO/IEC** 문서는 **유료(paywalled)**입니다(카탈로그 페이지만 공개). **ETSI**,
**OpenID Foundation**, **IETF/RFC**, **EU** 문서는 무료로 내려받을 수 있습니다.

---

## ISO/IEC

모바일 문서(mdoc) 데이터 모델, 근접 검색(proximity retrieval), 온라인 제시.

- **ISO/IEC 18013-5:2021 — Mobile driving licence (mDL) application** — SDK의 `mdoc` / `MDoc` 및
  `proximity` 모듈이 구현하는 mdoc 데이터 모델입니다: `IssuerSigned`/MSO, `DeviceResponse`, 선택적
  공개, 기기 인증(서명 및 MAC), 리더 인증, 그리고 §9 기기 검색(QR/NFC 인게이지먼트, BLE 세션 암호화).
  [ISO catalogue 69084](https://www.iso.org/standard/69084.html)
- **ISO/IEC TS 18013-7:2025 — mDL add-on functions** — mdoc의 온라인/브라우저 매개 제시: Digital
  Credentials API를 위한 오리진 결속 `SessionTranscript`와 HPKE로 봉인된 `org-iso-mdoc` 응답(Annex
  C), OpenID4VP 1.0 Final에 맞춘 Annex B 핸드오버.
  [ISO catalogue 91154](https://www.iso.org/standard/91154.html)
- **ISO/IEC 23220-1:2023 — Generic system architectures of mobile eID systems** — mdoc 구성 요소의
  기반이 되는 참조 아키텍처 및 라이프사이클 모델. [ISO catalogue 74910](https://www.iso.org/standard/74910.html)
- **ISO/IEC DTS 23220-2 (Draft, final text 2024-02-28) — Data objects and encoding rules for generic eID
  systems** — mdoc 구조가 기반으로 삼는 범용 CBOR 데이터 모델 / 인코딩 규칙입니다. 로컬 참고 사본은
  DTS 초안 텍스트이며, 발행된 Technical Specification은
  [ISO catalogue 86782](https://www.iso.org/standard/86782.html)입니다.
- **ISO/IEC TS 23220-3 (Working Draft WD13) — Issuing phase** — 모바일 eID 시스템의 크리덴셜
  발급/프로비저닝 단계에 대한 참조. 개발 중 — [iso.org](https://www.iso.org/)에서 "ISO/IEC 23220-3"
  검색(유료).
- **ISO/IEC 23220-4 (Draft, pre-RC5 consultation) — Operational phase** — 모바일 eID 시스템의
  운영(제시) 단계에 대한 참조. 개발 중 — [iso.org](https://www.iso.org/)에서 "ISO/IEC 23220-4"
  검색(유료).
- **ISO/IEC 7367 (Working Draft WD2) — Mobile documents** — mDL을 넘어선 mdoc의 일반화(모바일 문서 /
  mVC). 개발 중 — [iso.org](https://www.iso.org/)에서 "ISO/IEC 7367" 검색(유료).

---

## ETSI

eIDAS 2.0 신뢰 프레임워크: 인증서 프로파일, relying party 속성, 신뢰 목록. 모두 [ETSI standards
search](https://www.etsi.org/standards-search)에서 무료로 내려받을 수 있습니다.

- **ETSI TR 119 462 v1.1.1 — Wallet interfaces for trust services** — 지갑-신뢰서비스제공자 간
  인터페이스에 대한 정보성(informative) 참조. [ETSI standards search](https://www.etsi.org/standards-search#page=1&search=119%20462)
- **ETSI TS 119 411-8 v1.1.1 — Access certificate policy for wallet relying parties** — SDK의
  trust/registrar 경로가 검증하는 Wallet Relying Party Access Certificate(WRPAC)에 대한 인증서 정책.
  [ETSI standards search](https://www.etsi.org/standards-search#page=1&search=119%20411-8)
- **ETSI TS 119 412-6 v1.2.1 — Certificate profile for PID, Wallet and (Q)EAA providers** — SDK의
  발급자 및 Wallet Unit Attestation 서명자 인증서에 사용되는 X.509 인증서 프로파일(`id-etsi-qct-wal`).
  [ETSI standards search](https://www.etsi.org/standards-search#page=1&search=119%20412-6)
- **ETSI TS 119 461 v2.1.1 — Identity proofing** — 지갑 온보딩을 위한 신원 확인(identity proofing)
  요구사항(에코시스템에 대한 정보성 참조). [ETSI standards search](https://www.etsi.org/standards-search#page=1&search=119%20461)
- **ETSI TS 119 471 v1.1.1 — (Q)EAA provider policy** — (Q)EAA 제공자에 대한 정책 및 보안
  요구사항(발급자 측 참조). [ETSI standards search](https://www.etsi.org/standards-search#page=1&search=119%20471)
- **ETSI TS 119 472-1 v1.2.1 — EAA profiles: general** — 발급과 제시에 공통으로 적용되는 일반
  어테스테이션 프로파일 요구사항. [ETSI standards search](https://www.etsi.org/standards-search#page=1&search=119%20472-1)
- **ETSI TS 119 472-2 v1.2.1 — EAA profiles: presentation** — WRPRC 전송을 OpenID4VP
  `verifier_info`에 실리는 `registration_cert` 객체로 정의하며, SDK의 제시 신뢰 경로에서 소비됩니다.
  [ETSI standards search](https://www.etsi.org/standards-search#page=1&search=119%20472-2)
- **ETSI TS 119 472-3 v1.1.1 — EAA/PID issuance profiles** — 발급에 특화된 어테스테이션 프로파일
  요구사항. [ETSI standards search](https://www.etsi.org/standards-search#page=1&search=119%20472-3)
- **ETSI TS 119 475 v1.2.1 — Relying party attributes** — WRPRC 데이터셋에 실려 SDK의
  `WRPRCVerifier`가 확인하는 relying party 등록 속성 집합. [ETSI standards search](https://www.etsi.org/standards-search#page=1&search=119%20475)
- **ETSI TS 119 602 v1.1.1 — Trusted lists data model** — SDK의 `TrustConfig` 앵커(발급자 및
  등록기관 신뢰 목록)를 뒷받침하는 신뢰 목록 데이터 모델. [ETSI standards search](https://www.etsi.org/standards-search#page=1&search=119%20602)

---

## OpenID Foundation

발급 및 제시 프로토콜. 모두 무료로 읽을 수 있습니다.

- **OpenID for Verifiable Credential Issuance (OpenID4VCI) 1.0** — `openid4vci` 모듈이 구현하는
  발급 프로토콜(사전 인가 및 인가 코드 플로우, PAR, 서명된 메타데이터, 암호화된 요청/응답, 지연
  발급(deferred issuance), 키 증명(key-proof) 메커니즘). [openid.net](https://openid.net/specs/openid-4-verifiable-credential-issuance-1_0.html)
- **OpenID for Verifiable Presentations (OpenID4VP) 1.0** — `openid4vp` 모듈이 구현하는 제시
  프로토콜(DCQL 엔진, JAR 요청 해석, `vp_token`, `direct_post`/`direct_post.jwt`, DC API, 트랜잭션
  데이터). [openid.net](https://openid.net/specs/openid-4-verifiable-presentations-1_0.html)
- **OpenID4VC High Assurance Interoperability Profile (HAIP) 1.0** — SDK가 준수하는 필수
  부분집합(PAR/DPoP/PKCE, wallet & key attestation, 배치, 서명된 메타데이터)을 고정하는 상호운용성
  프로파일. [openid.net](https://openid.net/specs/openid4vc-high-assurance-interoperability-profile-1_0.html)

---

## IETF

크리덴셜 포맷, 상태(status), OAuth 구성 요소. 모두 무료로 읽을 수 있습니다.

- **RFC 9901 — Selective Disclosure for JSON Web Tokens (SD-JWT)** — `sdjwt` / `SdJwt` 모듈이
  구현하는 핵심 선택적 공개 JWT(발급/제시/검증, KB-JWT, 디코이(decoy)). [rfc-editor.org](https://www.rfc-editor.org/rfc/rfc9901)
- **draft-ietf-oauth-sd-jwt-vc (SD-JWT VC)** — `SdJwtVcVerifier`가 강제하는 SD-JWT 기반 검증 가능
  크리덴셜 포맷(typ/iss/vct, holder binding, 상태 추출). [datatracker.ietf.org](https://datatracker.ietf.org/doc/draft-ietf-oauth-sd-jwt-vc/)
- **draft-ietf-oauth-status-list (Token Status List)** — `statuslist` / `StatusList` 모듈이 가져와
  검증하는 상태/폐기 메커니즘. [datatracker.ietf.org](https://datatracker.ietf.org/doc/draft-ietf-oauth-status-list/)

또한 SDK에서 사용됨(발급 / OAuth 계층):

- **RFC 9449 — OAuth 2.0 Demonstrating Proof of Possession (DPoP)** — 발급 과정에서의 발신자
  제약(sender-constrained) 액세스 토큰. [rfc-editor.org](https://www.rfc-editor.org/rfc/rfc9449)
- **RFC 9126 — OAuth 2.0 Pushed Authorization Requests (PAR)** — 인가 코드 발급 플로우에서의 푸시
  인가 요청. [rfc-editor.org](https://www.rfc-editor.org/rfc/rfc9126)
- **RFC 7636 — Proof Key for Code Exchange (PKCE, S256)** — 발급 과정에서의 인가 코드 보호.
  [rfc-editor.org](https://www.rfc-editor.org/rfc/rfc7636)

포맷 & 암호(`SPEC-MATRIX.md`에 따라 구현됨, 참고 자료 세트에 PDF 없음):

- **RFC 8949 — CBOR** (결정론적 인코딩). [rfc-editor.org](https://www.rfc-editor.org/rfc/rfc8949)
- **RFC 9052 / 9053 / 9360 — COSE** (`COSE_Sign1`, 알고리즘, x5chain). [9052](https://www.rfc-editor.org/rfc/rfc9052) · [9053](https://www.rfc-editor.org/rfc/rfc9053) · [9360](https://www.rfc-editor.org/rfc/rfc9360)
- **RFC 7515 / 7518 — JOSE (JWS / JWE)** (compact ES256/384/512, ECDH-ES + A*GCM). [7515](https://www.rfc-editor.org/rfc/rfc7515) · [7518](https://www.rfc-editor.org/rfc/rfc7518)
- **RFC 9180 — HPKE** (base mode; DC API `org-iso-mdoc` 응답을 봉인). [rfc-editor.org](https://www.rfc-editor.org/rfc/rfc9180)
- **RFC 5280 — X.509 PKIX** (`trust` / `Trust` 모듈에서의 체인 검증). [rfc-editor.org](https://www.rfc-editor.org/rfc/rfc5280)

---

## EU / eIDAS

지갑이 목표로 하는 법적·아키텍처적 프레임워크.

- **EU Digital Identity Wallet — Architecture and Reference Framework (ARF)** — SDK의 에코시스템이
  준거하여 구축된 참조 아키텍처 및 기술 요구사항. [GitHub](https://github.com/eu-digital-identity-wallet/eudi-doc-architecture-and-reference-framework)
- **Regulation (EU) 2024/1183 (eIDAS 2.0)** — Regulation (EU) No 910/2014를 개정하며, European
  Digital Identity Wallet의 법적 근거입니다. [EUR-Lex](https://eur-lex.europa.eu/eli/reg/2024/1183/oj)
