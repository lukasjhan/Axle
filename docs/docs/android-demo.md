---
title: Android demo
---

# Android demo app

The repository ships a **debug wallet** app under `demo/` that drives the SDK on Android with Jetpack
Compose. It is the smallest realistic integration: three screens over the facade, three adapters.

## Screens

- **Credentials** — `wallet.credentials.list()` with parsed claims
- **Issue** — paste a credential-offer URI → `wallet.issuance` (pre-authorized + `tx_code`)
- **Present** — paste an `openid4vp://` request → `wallet.presentation` (resolve → consent → submit)

## Adapters (the whole integration surface)

```kotlin
Wallet.create(
    config = WalletConfig(),
    ports = WalletPorts(
        secureAreas = listOf(SoftwareSecureArea()),        // debug; use Android Keystore in production
        storage = FileStorageDriver(filesDir),             // adapters/FileStorageDriver.kt
        http = OkHttpTransport(),                           // adapters/OkHttpTransport.kt
    ),
)
```

## Build

The demo is a **separate Gradle project** that consumes the SDK as a composite build
(`includeBuild("../kotlin")`) — it does not affect the SDK's own build.

```bash
cd demo
./gradlew :app:assembleDebug        # → app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Toolchain: AGP 9.2.1, Gradle 9.5, `compileSdk` 36, `minSdk` 29.

:::note
Proximity (BLE) is device-only integration — implement a BLE `ProximityTransport` (GATT peripheral)
as described in the [Proximity guide](./guides/proximity). The proximity engine itself is complete
and unit-tested.
:::
