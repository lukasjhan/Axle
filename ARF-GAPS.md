# ARF 3.0.0 갭 분석

이 SDK가 **ARF 3.0.0** (2026-07-21)을 아직 충족하지 못하는 지점을 정리한다.
[SPEC-MATRIX.md](SPEC-MATRIX.md)의 짝이 되는 문서다. SPEC-MATRIX가 *기반 표준*
(OpenID4VCI/VP, 18013-5/-7, SD-JWT VC 등)을 추적한다면, 이 문서는 그 위에 얹히는
*ARF 고수준 요구사항(HLR)* 을 추적한다.

**방법.** ARF HLR 원본(`hltr/high-level-requirements.csv`, 키 컬럼 `Index`)을 태그 `v2.9.0`과
레포 HEAD(3.0.0, 2026-07-21) 사이에서 요구사항 단위로 기계 비교했다:
**총 725개 — 신규 41, 변경 195, 삭제 0**. 변경분은 텍스트 유사도로 실질 변경 105건과
편집상 변경(링크·마크업 정리) 90건으로 나눴고, 실질 변경만 평가했다. 각 항목은 실제 소스
트리와 대조했으며, 아래의 파일 참조는 추정이 아니라 직접 읽은 위치다.

분석일: **2026-07-29**. 2026-07-16의 ARF 2.9.0 평가를 대체한다.

심각도: **P0** = 현재 코드가 `SHALL`/`SHALL NOT`을 위반 · **P1** = 요구되는 기능이 부재 ·
**P2** = 요구되지만 외부 표준 대기 중이거나 사업자·조직 차원의 의무

별도 언급이 없으면 모든 갭은 Kotlin/Swift 양쪽 트리에 대칭이다(두 트리는 line-for-line 포팅 관계).

---

## 요약

| # | 클러스터 | 심각도 | 규모 |
|---|---|---|---|
| 1 | [Relying Party / Provider **Service identifier**](#1-service-identifier-topic-x-rr) | P1 | 큼 — registrar + 양쪽 트리 + 데모 |
| 2 | [트러스트 앵커: **LoTE vs Trusted List**](#2-트러스트-앵커-lote-vs-trusted-list) | P1 | 중간 |
| 3 | [**발급 시점** registration certificate 게이트](#3-발급-시점-registration-certificate-게이트) | P1 | 중간 |
| 4 | [registration certificate 전송 및 범위](#4-registration-certificate-전송-및-범위) | P1 | 중간 |
| 5 | [Digital Credentials API 공개 규칙](#5-digital-credentials-api-공개-규칙) | **P0** | 코드는 작고 결정이 큼 |
| 6 | [승인 화면 / User approval 규칙](#6-승인-화면--user-approval-규칙) | **P0** | 작음 |
| 7 | [임베디드 공개 정책 (EDP)](#7-임베디드-공개-정책-edp) | P1 | 큼, #1에 블록 |
| 8 | [폐지(revocation) 표면](#8-폐지revocation-표면) | P1 | 중간 |
| 9 | [WIA / KA 분리](#9-wia--ka-분리) | P1 | 중간 |
| 10 | [Wallet-to-wallet verifier 인증](#10-wallet-to-wallet-verifier-인증) | P2 | ETSI 대기 |
| 11 | [로깅, DPA 신고, 대시보드](#11-로깅-dpa-신고-대시보드) | P1 | 중간 |
| 12 | [ARF 2.9.0에서 이월](#12-arf-290에서-이월) | P1 | 큼 |
| 13 | [SDK 범위 밖](#13-sdk-범위-밖) | — | — |
| 14 | [FCAF — 신설 적합성 스위트](#14-fcaf--신설-적합성-스위트) | — | 기회 |

---

## 1. Service identifier (Topic X-rr)

**3.0.0에서 landed.** ARF 2.9.0에서는 진행 중(in-flight) 항목이었으나 이제 규범이 됐고,
두 번째 신원 축을 도입한다 — 등록 주체는 하나 이상의 **Service**를 등록하고, 인증서는
주체 식별자와 **함께** Service 식별자를 담는다.

| HLR | 요구사항 |
|---|---|
| Reg_33 | access certificate은 **Service identifier**를 담아야 하며, 해당 주체 범위 내에서 고유 |
| Reg_34 | access certificate은 표시 가능한 **Service trade name**을 담아야 함 |
| Reg_35 | access certificate **포맷**이 Reg_31–Reg_34a의 데이터 요소를 담을 수 있어야 함 |
| Reg_32a | 주체의 trade name과 식별자는 그 주체의 **모든** access cert에서 동일해야 함 |
| Reg_10a / Reg_10c | 주체는 Service를 등록하고, **Service마다** access cert 1개 이상 **및** registration cert 1개 이상을 받음 |
| Reg_10d / Reg_10e | RP는 Service별로 어떤 intended use가 적용되는지, 발급자는 Service별로 어떤 attestation 타입을 발급하는지 등록 |
| Reg_34a | intermediary access cert: CIR 2025/848 Annex I(16)의 "association" = (RP 식별자, RP **Service identifier**) 듀플렛 |
| RPRC_04 | registration cert: "association to the intermediary" = (intermediary 식별자, intermediary **Service identifier**) 듀플렛 |
| RPRC_04a | registration cert **포맷**이 Service identifier와 Service trade name을 담아야 함 |
| RPRC_07a | registration cert의 Service identifier + trade name은 그 주체의 access cert 중 하나와 동일해야 함 |
| RPRC_09 | **(intended use × Service)** 조합마다 registration certificate 1개 |
| RPRC_13 / RPRC_14 | PID/QEAA/PuB-EAA/EAA Provider에도 동일한 Service별 발급·배포 규칙 적용 |
| RPRC_10 | RP는 각 Instance에 그 Instance의 access cert와 Service identifier가 일치하는 reg cert만 보내야 함 |
| **RPRC_17a** | **Wallet은 reg cert와 access cert가 동일한 주체 식별자 *및* 동일한 Service identifier를 담는지 검증해야 함.** 불일치 시 User에게 경고하고, 그럼에도 승인을 허용할지는 Wallet Provider 정책이 결정 |

**현재 상태.**

- registrar의 WRPAC subject는 `CN / O / organizationIdentifier / C / email / phone / supportURI /
  policyOid` — `registrar-be/src/modules/access_cert/access_cert.service.ts:36-47`. **Service 축 없음.**
- WRPRC의 `intermediary` 객체는 `{sub, sname}` 뿐 —
  `kotlin/trust/.../WRPRCVerifier.kt:115-122`, `swift/Sources/Trust/WRPRCVerifier.swift:137-144`.
- 지갑의 신원 바인딩은 값 하나만 비교한다: `intermediary.sub ?: sub` 대 WRPAC의
  `organizationIdentifier` — `WRPRCVerifier.kt:129-135`. 주체 식별자 비교로는 올바르지만,
  두 번째로 비교할 대상이 아예 존재하지 않는다.
- registrar 데이터 모델에 Service 엔티티가 없다. `usesIntermediary`는 주체↔주체 링크이지
  (주체, Service) 듀플렛이 아니다.

**갭.** 축 전체. 영향 범위: registrar 스키마 + DTO + portal API + 인증서 프로파일 → WRPAC 발급
→ WRPRC 민팅 → `WRPRCVerifier`(양쪽 트리) → `VerifiedWRPRC` / `RegistrationInfo` 노출면 →
승인 화면. #7(EDP)의 인가 목록이 이 듀플렛을 키로 쓰므로 EDP를 블록한다.

**미해결 질문.** Service identifier가 X.509 subject와 WRPRC payload의 **어디에** 들어가는지는
ETSI TS 119 475 / TS 119 411-8이 정의해야 한다. Reg_35와 RPRC_04a가 포맷 확장을 명시적으로
요구하고 있으므로, 우리 인코딩을 자체 설계하기 전에 ETSI 개정판이 나왔는지 먼저 확인할 것.

---

## 2. 트러스트 앵커: LoTE vs Trusted List

3.0.0은 트러스트 앵커 배포를 두 갈래로 나누고 **둘 다** 지원할 것을 요구한다.

| 메커니즘 | 담는 대상 |
|---|---|
| **LoTE** — ETSI TS 119 602 | PID Provider, PuB-EAA Provider, Access Certificate Authority, Provider of registration certificates, Wallet Provider |
| **Trusted List** — ETSI TS 119 612 | QEAA Provider |

| HLR | 요구사항 |
|---|---|
| ISSU_10b | Wallet Provider **및 Wallet Unit**은 TS 119 612와 TS 119 602를 **모두** 지원해야 함 |
| OIA_15b | Relying Party와 RP Instance도 **모두** 지원해야 함 |
| ISSU_10a | Wallet Provider는 **정기적** 트러스트 앵커 관리를 수행: 최신 목록 다운로드, **추가된** 앵커를 Wallet Unit에 반영, 만료·폐지되었거나 주체가 무효화된 앵커는 **제거** |
| OIA_15a | Relying Party → RP Instance에 대해 동일한 정기 관리 의무 |
| ISSU_23 / ISSU_33 | Wallet은 해당 LoTE에 게시된 Access CA 앵커를 수용하되 **"오직 그것만"** |
| ISSU_33a / RPRC_02a / ISSU_23c | Wallet은 Provider-of-registration-certificate 앵커를 해당 LoTE에서 수용하되 **"오직 그것만"** |
| ISSU_09 / OIA_12 / OIA_14 | PID·PuB-EAA 서명 검증은 각각의 **LoTE** 앵커로 |
| ISSU_19 / ISSU_28 | PID/Attestation Provider는 WIA/KA를 LoTE의 Wallet Provider 앵커로 검증 |
| Reg_10b | Access CA는 자신의 LoTE 트러스트 앵커까지 이어지는 서명 인증서 + 중간 인증서도 함께 전달해야 함 |
| RPRC_02 | reg cert 서명자는 자신의 **LoTE** 앵커까지 이어지는 서명 인증서 + 중간 인증서를 JOSE `x5c`에 포함해야 함 |

**현재 상태.**

- 우리는 **TS 119 602만** 구현 — `kotlin/trustlist/.../TrustedListClient.kt`(파일 1개),
  `swift/Sources/TrustList/TrustedListClient.swift`, 샌드박스 퍼블리셔 `ecosystem/trusted-list`
  (JAdES 서명 LoTE 객체, `build-lote.mjs`). 트리 전체에 **TS 119 612 참조가 0건**.
- `TrustedListClient`는 fetch 후 `TrustConfig`에 넣는 게 전부다. **갱신 스케줄러도,
  `nextUpdate` 반영도, 앵커 제거 경로도 없다** — `kotlin/trustlist/`에서
  `refresh|cache|nextUpdate|ttl|interval` grep 결과 없음.
- registrar 앵커는 현재 **설정으로 핀**되어 있고 Commission이 게시한 LoTE에서 오지 않으므로,
  "오직 그것만" 조항을 강제할 지점이 없다.

**갭.** (a) QEAA Provider 앵커용 TS 119 612 XML Trusted List 파싱/검증. (b) 트러스트 앵커
수명주기: 스케줄 갱신, 추가 설치, 그리고 만료·폐지·주체 무효화 시 **제거**. (c) reg cert 및
Access CA 앵커를 핀 설정이 아니라 LoTE에서 조달.

---

## 3. 발급 시점 registration certificate 게이트

3.0.0은 발급자 등록 검증을 **차단성(blocking) 전제 조건**으로 바꿨다. 이전에는 권고였으나,
이제 네 개의 요구사항이 실패 시 **발급을 요청해서는 안 된다(SHALL NOT)** 고 명시한다.

| HLR | 요구사항 |
|---|---|
| RPRC_22 | Provider는 해당 **Service**의 registration certificate을 Credential Issuer metadata에 **값으로** 포함해야 함 (ETSI TS 119 472-3) |
| RPRC_22a | Wallet은 reg cert의 **형식·진위·유효성**을 검증. 부재/변형/위조/만료 → User 경고 **및 발급 요청 금지** |
| RPRC_22b | Wallet은 reg cert가 Provider metadata의 access certificate과 **동일한 고유 식별자**를 담는지 검증 → 아니면 경고 **및 발급 요청 금지** |
| RPRC_23 | Wallet은 **요청하려는 attestation 타입**이 Provider의 reg cert에 포함돼 있는지 검증 → 아니면 경고 **및 발급 요청 금지** |
| ISSU_24a | Wallet은 PID Provider reg cert의 `entitlement` 멤버(TS 119 472-3 §4.2.3)를 확인해 등록된 PID Provider인지 검증 → 아니면 경고 **및 요청 금지** |
| ISSU_24b | Wallet은 `providesAttestations`를 확인해 **PID 발급에 대해** 등록됐는지 검증 → 아니면 경고 **및 요청 금지** |
| ISSU_34a / ISSU_34b | QEAA / PuB-EAA / EAA Provider에 대한 동일한 두 검사 |

ISSU_23c와 RPRC_22b의 주석: 이 의무는 **CIR 2024/2982 개정 규정 발효 후 24개월**부터 적용된다.
시간 여유는 있으나 설계 비용은 동일하다.

**현재 상태.**

```kotlin
// kotlin/wallet/src/main/kotlin/com/hopae/eudi/wallet/IssuanceService.kt:280
issuerRegistered = metadata.signedMetadataVerified,
```
```swift
// swift/Sources/Wallet/IssuanceService.swift:269
issuerRegistered: metadata.signedMetadataVerified
```

`issuerRegistered`는 "발급자의 signed metadata가 검증됐다"는 의미일 뿐이다. **발급자
registration certificate을 가져오지도, 파싱하지도, 검증하지도 않는다.** `entitlement`와
`providesAttestations`는 `kotlin/openid4vci`, `kotlin/wallet`, `kotlin/trust` 어디에도 없다.

**갭.** `WRPRCVerifier`의 발급자 측 대응물이 필요하다: Credential Issuer metadata에서 값으로
실린 reg cert를 읽고(TS 119 472-3 §4.2.3), LoTE 기반 앵커(#2)로 검증하고,
`entitlement` / `providesAttestations` / 식별자 일치 / 요청 attestation 타입을 확인한 뒤
**발급 요청을 차단**해야 한다 — 지금은 아무것도 발급을 막지 않으므로 동작 변경이다.

---

## 4. registration certificate 전송 및 범위

| HLR | 요구사항 | 상태 |
|---|---|---|
| **RPRC_19** | RP Instance는 현재 Service *및* intended use에 해당하는 **단일** reg cert를 **모든** presentation request에 **값으로** 포함해야 하며, **근접·원격 양쪽 플로우** 모두에서 그렇게 해야 함 | 🟡 원격만 |
| RPRC_20 | RP Instance와 Wallet Unit은 ETSI TS 119 472-2의 **ISO/IEC 18013-5 확장** 또는 **OpenID4VP 확장**을 지원해야 함 (개정 CIR 2024/2982 Annex 2 반영) | 🟡 OpenID4VP만 |
| RPRC_21 | 속성 범위 검사. 초과 요청 시 Wallet Provider 정책이 (a) 미등록 포함 전체 승인 허용, (b) 등록된 것만 승인 허용, (c) 전체 거부 중 선택 | 🟡 검사는 함, 정책 노브 없음 |
| RPRC_06 / RPRC_07 | reg cert의 trade name과 식별자가 access cert의 것과 동일 | ✅ 식별자 / trade name은 교차 검증 안 함 |
| RPRC_11 | reg cert는 데이터 삭제 연락처(웹 폼 URL, 이메일, **또는** 전화번호)를 담아야 함 | ⬜ 노출 안 함 |
| RPRC_01a / RPRC_01b | 유효기간 24시간 초과 reg cert는 TS 119 475에 따라 폐지 가능해야 하고, 발급자는 폐지 정책 보유 | ✅ 지갑 측은 `status` 확인 |

**현재 상태.** WRPRC는 OpenID4VP 요청의 `verifier_info`(값으로 실린 `registration_cert` +
`registrar_dataset`)에서만 읽는다 — SPEC-MATRIX의 "WRPRC / dataset transport" 행 참조.
`kotlin/proximity`와 `kotlin/mdoc`에서 `wrprc|euWrprc|registration_cert`를 grep하면 **결과가 없다.**
즉 mdoc 근접 요청에는 registration certificate이 실리지 않고, 지갑도 읽을 곳이 없다.
RPRC_21은 구현돼 있으나(`PresentationService.kt:182-184`, `Presentation.kt:73`에 노출)
결과가 정보성이며 (a)/(b)/(c)를 고를 수 있는 정책 설정이 없다.

**갭.** ETSI TS 119 472-2의 18013-5 확장(device request 측, holder + reader), RPRC_21의 3택
정책 노브, 그리고 Topic L 데이터 삭제 플로우를 위한 RPRC_11 삭제 연락처 노출.

---

## 5. Digital Credentials API 공개 규칙

**현재 코드가 `SHALL NOT`을 능동적으로 위반하는 유일한 지점이다.**

| HLR | 요구사항 |
|---|---|
| **OIA_08e** | Wallet은 기본적으로 저장된 모든 attestation의 존재를(**즉 그 attestation 타입을**) DC API 프레임워크에 공개하되, **그 안의 속성의 존재도, 값도 공개해서는 안 된다** |
| **OIA_08f** | Wallet은 DC API 프레임워크로의 공개를 끄는 **전역 User 설정**을 제공해야 하며, 껐을 때 개별 attestation을 선택해 공개하도록 하는 것이 권장됨 |
| OIA_08g | **교차 기기** DC API 플로우에서 Wallet은 RP Instance가 **물리적으로 근접**해 있음을, 안전하고 직접적이며 사용자 매개된 로컬 채널(CTAP BLE proximity engagement / hybrid transport)로 검증해야 함 |
| OIA_08c / OIA_08d | Wallet은 리디렉트 기반 교차 기기 플로우를 지원하지 않는 것이 권장됨. 이를 쓰는 RP는 ARF §4.4.3.1의 완화책을 구현해야 함 |
| WIAM_13a | Wallet **리셋** 시, 이전에 공개했던 attestation을 더 이상 보관하지 않는다는 사실을 DC API 프레임워크에 알려야 함 |
| PAD_05 | User 요청으로 attestation을 **삭제**한 경우에도 동일한 의무 |

**현재 상태.**

```kotlin
// android/dcapi/src/main/kotlin/com/hopae/eudi/wallet/android/dcapi/DcApiRegistrar.kt:87
private fun field(displayName: String, value: String) =
    Cbor.Array(listOf(txt(displayName), txt(value), txt(if (value.length < 128) value else "")))
```

`DcApiRegistrar.kt:111-128`에서 만드는 레지스트리 payload는 `issued.claims`를 순회하며
credential마다 **claim 이름과 그 표시 값**의 namespace/claim 맵을 내보낸다 — mdoc(`namespaces`)과
SD-JWT VC(`claims`) 양쪽 다. 이것이 정확히 OIA_08e가 금지하는 "속성의 존재 … 그리고 그 값"이다.

- OIA_08f: 그런 설정이 데모에도 SDK에도 없다.
- OIA_08g: 미구현. 실무적으로 근접 확인은 플랫폼의 CTAP hybrid transport가 수행하며 지갑
  통제 밖이지만, `SHALL`은 Wallet Unit에 걸려 있다.
- WIAM_13a / PAD_05: **Android에서는 사실상 충족** — `MainActivity.kt:94-95`가 매
  `w.credentials.changes` 방출마다 `DcApiRegistrar.register(...)`를 재실행하고, `register`는
  현재 credential 집합으로 레지스트리를 통째로 다시 만들므로 삭제가 전파된다. 리셋 경로가
  change를 방출하는지는 확인 필요. **iOS에는 DC API 연동이 없어** 이 의무가 현재는 공허하다.

**갭 / 결정 사항.** OIA_08e는 Android credential-manager 매처의 동작 방식과 구조적으로 충돌한다:
번들된 WASM 매처가 **레지스트리를 대상으로** DCQL을 로컬 평가하므로, 레지스트리에서 claim을
빼면 지갑을 깨우지 않고는 매칭이 불가능하다. 한 줄 수정이 아니라 설계 결정(무엇을 등록하고
매처가 무엇을 필요로 하는가)이며, 코드를 건드리기 전에 결론을 내야 한다.

---

## 6. 승인 화면 / User approval 규칙

작고 독립적이며, 현재 위반 중이다.

| HLR | 요구사항 | 상태 |
|---|---|---|
| **RPI_07** | intermediary를 통한 요청일 때, Wallet은 승인을 요청하면서 **intermediary와 intermediary Service의 trade name을 표시해서는 안 된다** | ❌ 위반 |
| RPA_07b | access cert / reg cert 검증 **실패**를 경고할 때, 승인은 **명시적**이어야 함 — 침묵이나 사전 체크된 박스는 불가 | ⬜ |
| RPA_07c | 요청에 PID **`portrait`** 이 포함되면 Wallet은 **생체정보**가 관련됨을 경고하고 **명시적** 승인을 받아야 함 | ⬜ |
| RPA_01a / RPA_07a | Wallet은 RP 인증과 User 승인 과정에 대해 **완전한 권한**을 유지해야 하며, 이 과정을 **브라우저와 운영체제를 포함한** 제3자가 처리해서는 안 됨 | 🟡 DC API 경로 재검토 필요 |
| RPA_10 | 승인 화면은 intended use 설명 **과 개인정보 처리방침 링크**를 표시해야 함 | 🟡 purpose는 노출, 링크 렌더링 확인 필요 |
| PID_03 | PID Provider는 User가 `portrait` 수령을 거부하도록 할 수 있으며, 그 경우 해당 속성은 **빈** JSON string / CBOR bstr | ⬜ 빈 portrait 렌더링 미확인 |

**현재 상태.** 두 데모 모두 intermediary를 부제로 렌더링한다:

- `demo/app/src/main/kotlin/com/hopae/eudi/demo/ui/screens/PresentScreen.kt:227` — `"via $it"`
- `demo-ios/AxleWallet/AxleWallet/PresentView.swift:360` — `"via \(intermediary)"`

intermediary를 **로그에 남기는 것은 올바르고 요구되는 동작**이다(`TransactionLog.intermediaryName` /
`intermediarySub`를 통해 트랜잭션 로그에서 계속 보인다). 표시하면 안 되는 것은 **승인 화면**뿐이다.
데모 어디에도 portrait 전용 처리는 없다 — `biometric` 검색 결과는 전부 온보딩 잠금 해제 플로우다.

RPA_01a/RPA_07a는 OS와 브라우저를 명시적으로 지목하게 됐으므로 별도 점검이 필요하다: DC API
경로에서는 credential *선택*이 우리 액티비티가 뜨기 전에 플랫폼 UI에서 일어난다.

---

## 7. 임베디드 공개 정책 (EDP)

CIR 2024/2979 Annex III에 따라 의무이며, SDK에 **전혀 없다**(`disclosure.?polic`,
`credential_reuse_policy`, `119 472-3` 파싱 모두 지갑 트리에서 0건). 3.0.0은 명세를 구체화했다:

| HLR | 요구사항 |
|---|---|
| EDP_02 | 'Authorised relying parties only' 정책 = Reg_32/Reg_33에 따른 (RP 식별자, **Service identifier**) **듀플렛** 목록. 요청 수신 후 Wallet은 **registration certificate**에서 둘을 꺼내 목록과 대조하고, 없으면 정책 평가 실패로 보고 User에게 알림 |
| EDP_03 | 'Specific root of trust' 정책 = 루트/중간 인증서 목록. Wallet은 **registration certificate을 서명한 체인의 모든 인증서**를 이 목록과 대조하고, 하나도 없으면 실패 처리 후 User에게 알림 |
| EDP_06 | 평가는 reg cert 정보와 함께, ETSI TS 119 472-3의 평가 규칙에 따라 수행 |
| EDP_08 | 정책 포맷은 ETSI TS 119 472-3을 따라야 함 |
| EDP_09 | Attestation Provider는 정책을 Issuer metadata에 **값으로** 포함해야 함 (OpenID4VCI + TS 119 472-3) |

**갭.** 전부. 발급 시점에 issuer metadata에서 정책을 파싱하고, credential과 함께 저장하고,
제시 시점에 WRPRC를 대상으로 **오프라인** 평가해야 한다. EDP_02가 Service identifier 듀플렛을
키로 쓰므로 **#1에 블록**된다.

---

## 8. 폐지(revocation) 표면

| HLR | 요구사항 | 상태 |
|---|---|---|
| VCR_01b | SD-JWT VC PID/QEAA/PuB-EAA: 유효기간 24시간 이하 **또는** Token Status List. **JSON ARL 규격은 존재하지 않음** | ✅ Token Status List 구현됨 |
| VCR_11a | SD-JWT VC 상태는 IETF **Token Status List**를 써야 함 | ✅ |
| VCR_11 | mdoc: 개정 CIR 2024/2979 Annex 2에 따른 Attestation Status List **또는** Attestation Revocation List | 🟡 status list만, ARL 미구현 |
| VCR_13 | RP Instance는 수신 시 폐지 확인이 **권장**되며, 하지 않으려면 위험 분석을 문서화해야 함 | 🟡 verifier-be |
| VCR_19 | Wallet Instance는 자신의 PID/attestation **및 자기 자신 / WSCD / keystore**의 폐지 여부를 주기적으로 확인하고 User에게 통지하는 것이 권장됨 | ⬜ |
| VCR_12a | Provider는 **WIA/KA** 폐지 상태 확인 메커니즘을 지원해야 함 | ⬜ (#9 참조) |
| VCR_04 | 폐지는 되돌릴 수 없음 — PID, attestation, **WIA, KA** 모두 | 지갑 측 해당 없음 |
| Reg_12 / Reg_13 | Access CA는 유효기간 24시간 초과 access cert를 폐지할 수 있어야 하고 폐지 정책을 보유해야 함 | ⬜ CRL/OCSP 전무 |
| RPRC_01a / RPRC_01b | registration cert에 대해 TS 119 475 기준 동일 | ✅ WRPRC `status` 노출·확인 |

**갭.** access certificate 폐지 확인은 메커니즘 자체가 없다(SPEC-MATRIX가 이미 CRL/OCSP를 ⬜로
기록하고 있는데, 이제 그 행이 실질적 무게를 갖는다). mdoc ARL 변형. 그리고 자기 자신/WSCD/
keystore 상태까지 포함하는 VCR_19의 주기적 자가 점검 루프.

---

## 9. WIA / KA 분리

2.9.0 평가(TS3 v1.5.2)에서 이월됐고 3.0.0에서 강화됐다.

| HLR | 요구사항 |
|---|---|
| **WUA_09a** | PID 또는 device-bound attestation 발급 시, Provider는 Wallet Unit에서 받은 **KA에 attest된 공개키 중 하나**에 바인딩해야 함 |
| WUA_32 | 남은 **revocation maintenance period**에 대한 최소 요건이 있는 Provider는 발급 시점에 이를 TS3에 따라 Wallet Unit에 전달해야 함 |
| WURevocation_03 | WP 정책은 WIA / WSCD용 KA(NCP+) / keystore용 KA(NCP)를 구분해야 함 |
| WURevocation_09a | (특정 종류의) WSCA/WSCD 또는 keystore의 신뢰성에 영향을 주는 침해가 감지되면 해당 종류를 폐지해야 함 |
| WIAM_05 | WP는 KA와 WIA 발급에 필요한 범위에서 기기 및 가용한 **WSCA/WSCD와 keystore** 정보를 처리 |

**현재 상태.** `key_storage_status`는 0건이고, `oauth-client-attestation`은 WUA 클라이언트 인증
경로에 쓰인다. 우리 네이밍은 이미 두 엔드포인트를 분리하고 있으나(WUA = 클라이언트 인증,
key attestation = 발급별 증명키), **TS3 v1.5.2의 클레임 집합**(WIA의 `wallet_name`,
`wallet_version`, `client_status`; KA의 `key_storage_status`; WIA TTL 24시간 미만; KA 단회 사용;
WSCD/keystore마다 KA 1개)이 모델링돼 있지 않고, WUA_32의 revocation-maintenance-period 협상도 없다.

---

## 10. Wallet-to-wallet verifier 인증

| HLR | 요구사항 |
|---|---|
| W2W_23 | Verifier Wallet은 자신이 인정된 Wallet Provider의 진본이며 폐지되지 않은 Wallet Unit이라는 암호학적 증명을, **프로토콜 세션에 바인딩하여** 포함해야 함 — *"공통 방식이 기술 명세로 확립되어 있다면"* |
| W2W_24 | Holder Wallet은 요청을 User에게 보이기 전에 그 증명을 검증해야 함 |
| W2W_25 | 실패 시 User에게 통지하고, 거부하거나 User가 선택하게 해야 함 |

**갭.** 실재하지만 **P2: 이를 가능하게 하는 ETSI 명세가 아직 없다**(주석에 "ETSI에서 개발 중"이라
명시). W2W_23은 그 명세가 나올 때까지 스스로 유예된다. Topic 30에서 변경된 나머지
(W2W_14/15/19/21)는 2.9.0 대비 편집상 변경이다.

---

## 11. 로깅, DPA 신고, 대시보드

| HLR | 요구사항 | 상태 |
|---|---|---|
| RPT_DPA_01 | Wallet은 의심스러운 요청을 **DPA**에 신고하는 과정을 User가 시작할 수 있게 해야 하고, 해당 RP를 감독하는 DPA의 연락처를 **로그 항목(DASH_03)에서** 제공해야 함 | ⬜ |
| DASH_09b | Wallet Provider와 Wallet Unit은 **TS1(EUDI Wallet Trust Mark)** 및 CIR 2024/2979 제14a조를 준수해야 함 | ⬜ |
| — | TS10 트랜잭션 로그 항목 유형(W2W, pseudonym, 서명, 삭제, DPA 신고) + PBES2 JWE 내보내기 | ⬜ 2.9.0에서 이월 |
| — | **Migration Object** (Topic N 이식성) | ⬜ 2.9.0에서 이월 |

우리 `txlog`는 presentation과 issuance를 claim path + null 값으로 기록하지만(DASH_03a 충족),
DPA 연락처도 추가 TS10 항목 유형도 담지 않는다.

---

## 12. ARF 2.9.0에서 이월

여전히 미해결이며, 3.0.0에서 변화가 없거나 오히려 날카로워진 항목:

1. **SD-JWT VC Type Metadata (§4)** 와 `vct#integrity` — 기반 표준 갭 중 최대. TS12/SCA의
   `transaction_data_types` 검증의 전제. SPEC-MATRIX 참조.
2. **Unlinkability Method A/B (ISSU_37–50)** — once-only / limited-time attestation 관리,
   ETSI TS 119 472-3 §4.2.4.2의 `credential_reuse_policy`(트리 내 0건), low-water-mark 배치 재충전,
   마지막 technical attestation은 파기 금지(WIAM_21).
3. **키 저장소 등급 협상**(ISSU_27d, OpenID4VCI §12.2.4 + D.2) — `iso_18045_*` 등급 미파싱,
   keystore 대 WSCD 선택 로직 없음.
4. **access certificate에 대한 Certificate Transparency**(CT_05/06) — CT 인프라 존재가 전제.
5. **Pseudonym** — 로컬 CRUD만. Topic E-rr에서 WebAuthn은 선택으로 완화됨.
6. **ETSI TS 119 432 기반 QES** — `transaction_data` 위에 얹힘. CSC API / PAdES는 범위 밖.
7. **ISSU_33b (신규)** — Wallet Solution은 Commission의 attestation scheme 카탈로그
   (CIR 2025/1569 제8조)에 등록된 모든 스킴 중 우리가 이미 지원하는 포맷·발급 프로토콜을 쓰는
   것을 지원해야 한다. 코드 변경이라기보다 적합성 표면의 의무지만, attestation 처리가
   얼마나 범용적이어야 하는지를 제약한다.
8. **ISSU_02 (변경)** — attestation 포맷에 "…**ETSI TS 119 472-1**에 문서화된 추가 및 변경사항"이
   붙었다. 이 참조를 우리 mdoc / SD-JWT VC 프로파일과 대조해봐야 한다.

---

## 13. SDK 범위 밖

이 문서가 to-do 목록으로 오독되지 않도록 명시한다. 아래는 3.0.0에서 실질적으로 변경됐지만
Member State·Commission·사업자 조직 차원의 의무이며 지갑/SDK 코드 표면이 없다:

- **Notification 토픽** — GenNot_*, PPNot_*, PuBPNot_*, RPACANot_*, WPNot_*, TLPub_*
  (Topic 31: 회원국이 Commission에 사업자·CA를 통보하는 절차).
- **사업자 정책 요구사항** — ISSU_67(PID Provider NCP+), ISSU_69(QEAA QCP-n/l-qscd),
  ISSU_72(PuB-EAA NCP+), WURevocation_03(WP 정책), Reg_11/12/13(ETSI TS 119 411-8 기반
  Access CA 정책), RPRC_01b(reg cert 폐지 정책), QTSPAS_01/02.
- **Registrar / 회원국 절차** — Reg_01b(투명성 목적 수집만, 사전 인가 금지),
  RPI_04(intermediary 관계에 대한 법적 유효 증거).
- **Rulebook 차원** — PID_01, mDL_01, ARB_*(rulebook은 이제
  `eudi-doc-attestation-rulebooks-catalog`에 있음), PID_03a(RP의 portrait 보유 금지 —
  Relying Party의 법적 의무이지 지갑의 통제 수단이 아님).

이 중 일부는 SDK 의무가 아니더라도 `ecosystem/` 서비스(registrar, issuer-be, verifier-be)에
샌드박스 구현으로는 내려온다 — Reg_10b(Access CA가 체인을 함께 전달)와 RPRC_02(reg cert `x5c`가
LoTE 앵커까지 이어짐)가 구체적인 예다.

---

## 14. FCAF — 신설 적합성 스위트

3.0.0은 **7.5절 Functional Conformance**를 신설하고 **Functional Conformance Assessment
Framework**를 도입했다 — CIR 2024/2981 Annex III에 따라 Wallet Solution이 지원해야 하는 기능
요구사항에 대한 공용·재사용 테스트 케이스 집합이며 **conformance.eudi.dev**에 게시된다.
§§7.2–7.3의 보안 평가를 대체하지 않고 보완한다.

지갑에 대한 최초의 공식 외부 잣대다. 여기에 돌려보면 이 문서의 수기 추정 중 상당 부분이 실측
결과로 대체되며, #1–#12의 작업 순서를 확정하기 전에 먼저 수행하는 것이 합리적이다.

---

## 검증 노트

위 주장들은 소스와 대조했다. **직접 읽은** 위치:
`registrar-be/src/modules/access_cert/access_cert.service.ts:36-47` ·
`kotlin/trust/.../WRPRCVerifier.kt:100-159` · `swift/Sources/Trust/WRPRCVerifier.swift:135-190` ·
`kotlin/wallet/.../IssuanceService.kt:280` · `swift/Sources/Wallet/IssuanceService.swift:269` ·
`kotlin/wallet/.../PresentationService.kt:182-193` ·
`android/dcapi/.../DcApiRegistrar.kt:63-128` · `demo/app/.../MainActivity.kt:94-95` ·
`demo/app/.../ui/screens/PresentScreen.kt:218-235` · `demo-ios/.../PresentView.swift:360` ·
`kotlin/trustlist/`(파일 1개) · `ecosystem/verifier-be/tools/mint-intermediary-rp.mjs`.

`kotlin/`, `swift/`, `demo/`, `demo-ios/`, `android/`, `ecosystem/` 전반에서 **grep으로 부재를
확인한** 것: `119 612`, `disclosure.?polic`, `credential_reuse_policy`, `type.?metadata`,
`key_storage_status`, `providesAttestations`, 그리고 `kotlin/proximity` / `kotlin/mdoc` 내의
`wrprc|registration_cert`.

**독립적으로 검증하지 않은 것**(SPEC-MATRIX에서 추론했거나 런타임 확인이 필요):
Wallet 리셋 경로가 `credentials.changes` 이벤트를 방출하는지(#5), 개인정보 처리방침 링크
렌더링(#6, RPA_10), verifier-be의 폐지 확인(#8, VCR_13).
