---
title: Android 데모
---

# Android 데모 앱

리포지토리의 `demo/`에는 Jetpack Compose로 SDK를 구동하는 **디버그 월렛** 앱이 있습니다. 파사드 위의 세 화면, 세 어댑터로 구성된 가장 현실적인 최소 통합입니다.

## 화면

- **Credentials** — `wallet.credentials.list()`로 파싱된 클레임 표시
- **Issue** — 크리덴셜 오퍼 URI 붙여넣기 → `wallet.issuance` (사전인가 + `tx_code`)
- **Present** — `openid4vp://` 요청 붙여넣기 → `wallet.presentation` (resolve → 동의 → 제출)

## 어댑터 (통합 표면 전부)

```kotlin
Wallet.create(
    config = WalletConfig(),
    ports = WalletPorts(
        secureAreas = listOf(SoftwareSecureArea()),        // 디버그용; 프로덕션은 Android Keystore
        storage = FileStorageDriver(filesDir),             // adapters/FileStorageDriver.kt
        http = OkHttpTransport(),                           // adapters/OkHttpTransport.kt
    ),
)
```

## 빌드

데모는 SDK를 composite build(`includeBuild("../kotlin")`)로 소비하는 **별도 Gradle 프로젝트**입니다 — SDK 자체 빌드에는 영향이 없습니다.

```bash
cd demo
./gradlew :app:assembleDebug        # → app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

툴체인: AGP 9.2.1, Gradle 9.5, `compileSdk` 36, `minSdk` 29.

:::note
근접(BLE)은 기기 전용 통합입니다 — [근접 가이드](./guides/proximity)처럼 BLE `ProximityTransport`(GATT 페리페럴)를 구현하세요. 근접 엔진 자체는 완성·단위테스트되어 있습니다.
:::
