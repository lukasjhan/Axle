# EUDI Wallet — 프로덕션 Android 앱 계획 (작업용, 완성 후 삭제)

## 목표
`demo/app`을 데모 툴에서 **팔 수 있는 수준의 실제 소비자 지갑**으로 리빌드. SDK는 우리가 만든 걸 그대로 사용.
iOS는 다음. 디자인(Claude Design)은 **느낌 가이드**일 뿐, 플로우는 진짜 지갑 플로우.

## 원칙
- 진짜 플로우 + 진짜 SDK. Mock 없음 — 홈은 실제 발급된 것만 표시.
- 디자인은 느낌만(Manrope, 네이비→블루 그라디언트, 둥근 카드, 초록 신뢰 체크). 샘플 콘텐츠는 placeholder.
- 디버그는 충실히 유지하되 Settings 아래로.

## 확정된 결정
- **A. 크리덴셜 선택 API를 SDK에 추가** (매칭 후보 >1이면 사용자가 선택). `PresentationSelection.auto` 외 경로.
- **C. PIN = 실제 비밀** — 앱 잠금 해제 + 키 사용 게이팅(`setUserAuthenticationRequired`).
- **E. `demo/app` 자리에서 리빌드** — 이게 THE 지갑.
- **Reader auth (양방향):**
  - 근접 **홀더**(내 mDL 제시): 리더 인증을 reader CA(트러스트 리스트)에 검증 → trusted 뱃지. **SDK 이미 됨**(`ProximityService.verifyReader`, `request.reader.trusted`), UI만.
  - **Read mDL**(검증자 모드): 우리 리더가 **reader auth 서명**하도록 추가 — 리더 키+인증서(reader CA 체인)를 지갑에 프로비저닝, `ReaderAuthSigner` 주입. **SDK 추가 필요**.

## 이번 작업이 건드릴 SDK (최소)
1. 크리덴셜 선택 API (양쪽 언어).
2. Read-mDL 리더 auth 서명 (양쪽 언어 + 리더 인증서 프로비저닝).
- 그 외 UI는 기존 SDK 표면 그대로 사용.

## 플로우 교정 (반영됨)
1. 제시 클레임 **읽기 전용**(verifier DCQL이 결정, 필수=잠금). 선택적 부분만 포함/제외 토글.
2. 매칭 다수면 **크리덴셜 선택**.
3. **DC API 제시**(Credential Manager / `GetCredentialActivity`) 1급 경로, 같은 consent UI 재스타일.
4. **온보딩** 추가(PIN·생체 설정, 키 프로비저닝).
5. **QR 스캔 통합 (홀더 측만)** — 홀더로서 받는 스캔은 **스캐너 1개(`ScanRouter`)**로 통합.
   스킴 분기: offer→발급, openid4vp→제시, 미인식→에러. 딥링크도 같은 라우터로.
   스캐너를 안 거치는 것: 근접 제시(내 engagement QR을 *보여줌*), DC API(OS 호출).
   **Read mDL(검증자 모드)의 카메라는 분리 유지** — 남의 device engagement를 스캔하는 별개 컨텍스트(현 구조 유지).

## 화면
온보딩 · 앱잠금 · 홈 · 문서상세 · 발급(5스텝) · 제시(QR+근접) · DC API 제시 · Read mDL(검증자) ·
Activity · Settings · Debug log. 각 화면은 `wallet.issuance/presentation/credentials/reader/transactions`로 구동.

## 재사용 / 신규
- **재사용:** `DemoWallet.kt`(SDK 배선), `android/core`(SecureArea·저장·HTTP), `android/proximity`(BLE/NFC),
  `android/dcapi`+`GetCredentialActivity`, `android/attestation`(Play Integrity·키 attestation), `ProximityScreens.kt`(재스타일).
- **재작성:** `WalletApp.kt` → 화면별 파일로 분리.
- **신규:** `ui/theme`(색·폰트·테마), `ui/components`(카드·PIN패드·스텝바·세그먼트·뱃지), `ui/screens`,
  `security`(AppLock PIN 해시 + Biometric), `nav`(Navigation-Compose + 경량 ViewModel).
- **새 의존성:** navigation-compose, androidx.biometric, security-crypto, 번들 폰트(Manrope·JetBrains Mono).

## 프로덕션 하드닝
- Secure Area/WSCD: StrongBox 가능 시 강제, TEE 폴백, 활성 WSCD를 Settings/Debug에 노출.
- 키 사용 게이팅: 서명키 `setUserAuthenticationRequired(true)`.
- 앱 잠금: PIN(salted hash) + 생체, 콜드스타트/재개 시.
- 신뢰: 이미 배선(issuer/reader/registrar + WRPRC + status list). 2A/2B 라벨 흐름, TSL 신선도 노출.

## 단계 (각 단계 = 기기 설치 가능한 증분)
- **P0** 디자인시스템 + 테마/폰트 + 내비 셸(바텀탭 Home/Activity/Settings)
- **P1** 온보딩 + 앱잠금 + 생체/PIN + Secure-Area/StrongBox 강제 + 키 게이팅
- **P2** 홈 + 문서 상세
- **P3** 발급 플로우(재스타일, 실 SDK, 2A/2B)
- **P4** 제시 플로우 QR+근접(크리덴셜 선택, 읽기전용 클레임, 리더 뱃지, PIN/생체, activity)
- **P5** DC API 제시
- **P6** Read mDL 모드 + **리더 auth 서명(SDK 추가)**
- **P7** Activity + Settings + Debug
- **P8** 폴리시 + 기기 QA

## SDK 추가 순서
- **A(크리덴셜 선택)** 는 P4 직전에.
- **리더 auth 서명** 은 P6에서.
