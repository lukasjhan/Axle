# Axle Wallet — release & tester distribution

How the demo app is branded, signed, and handed to testers via **Google Play internal testing** — the path
that makes it a Play-recognised build. For the Play Integrity attestation details (Google Cloud project,
service account, reading the verdict) see [`../wallet-provider/PLAY-INTEGRITY.md`](../wallet-provider/PLAY-INTEGRITY.md).

## App identity

- **`applicationId` `com.hopae.axle.wallet`** — the identity Play and Play Integrity use; **fixed once
  published**. Label **“Axle Wallet”**, adaptive launcher icon (EU palette). Only the app was rebranded; the
  code package stays `com.hopae.eudi.demo` (internal, invisible).

## 1. Release (upload) signing

Play needs a **signed** build, and the local *debug* key is not Play-recognised — so we sign with a dedicated
**upload key**.

- Keystore + credentials live in `demo/upload-keystore.jks` and `demo/keystore.properties` — **both
  gitignored, never committed.** Generate one with:
  ```sh
  keytool -genkeypair -v -keystore demo/upload-keystore.jks -alias upload \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass <pw> -keypass <pw> -dname "CN=Axle Wallet, O=Hopae, L=Seoul, C=KR"
  ```
  ```properties
  # demo/keystore.properties
  storeFile=upload-keystore.jks
  storePassword=<pw>
  keyAlias=upload
  keyPassword=<pw>
  ```
- `demo/app/build.gradle.kts` has a release `signingConfig` that reads `keystore.properties`; on machines
  without it the release build simply stays unsigned (debug still works).
- **Back the upload keystore up** — it's the key Play verifies your uploads with.

## 2. Build the AAB

```sh
cd demo && ./gradlew :app:bundleRelease
# → app/build/outputs/bundle/release/app-release.aab
keytool -printcert -jarfile app/build/outputs/bundle/release/app-release.aab | grep Owner   # → CN=Axle Wallet
```

R8/minification is left **off** (the wallet uses CBOR/JOSE reflection).

## 3. Play Console — create the app

[play.google.com/console](https://play.google.com/console) → **Create app**: name “Axle Wallet”, package
`com.hopae.axle.wallet` (permanent, must match the AAB).

**Play App Signing** (accept the default): Google generates and manages the **app signing key**. Our keystore
is only the **upload key** — Google re-signs the delivered APKs with the app signing key, which is why a
Play-distributed build reports `appIntegrity: PLAY_RECOGNIZED`. Do **not** choose “upload your own app signing
key”.

## 4. Internal testing track (no public review)

**Test and release → Testing → Internal testing → Create release → upload the AAB.** Fill the one-time
activation forms (content rating, data safety, target audience); internal testing publishes near-instantly —
no review wait.

## 5. Testers

- **Internal testing → Testers** → create an email list → add tester emails.
- Copy the **opt-in (“test participation”) link**, open it on the phone, join, then **install from Play**.
- The app **must be installed via Play** (not side-loaded) to be `PLAY_RECOGNIZED`.

## 6. Building & releasing from another machine (key recovery)

Everything signing-specific is **gitignored**, so a fresh clone can't sign a release until you restore the
machine-local key material. Keep a **recovery bundle** (zip) of these off the repo, in a password manager /
encrypted volume — see the bundle's own `RECOVERY.md` for the exact restore steps.

| File (gitignored)                              | Restore to the same path · role |
|------------------------------------------------|---------------------------------|
| `demo/upload-keystore.jks`                     | Play **upload key** — must be *identical* on every machine (Play rejects a differently-signed AAB). Losing it → request an upload-key reset in Play Console (the Google-held app-signing key is unaffected, so user updates keep working). |
| `demo/keystore.properties`                     | keystore path + passwords (`storeFile=upload-keystore.jks`, relative to `demo/`). |
| `demo/app/src/main/assets/reader_wrpac.json`   | reader-auth identity (optional — absent → Read-mDL requests unsigned, holder shows the reader "unverified", app still works). |

Recreate **per machine** (do not carry these — the SDK path is machine-local):

```sh
echo "sdk.dir=$ANDROID_HOME" > demo/local.properties
echo "sdk.dir=$ANDROID_HOME" > android/local.properties
```

Then restore the three files above and build:

```sh
cd demo
./gradlew :app:assembleDebug   # debug APK → adb install -r app/build/outputs/apk/debug/app-debug.apk
./gradlew :app:bundleRelease    # signed AAB → app/build/outputs/bundle/release/app-release.aab
```

**Bump `versionCode`** in `demo/app/build.gradle.kts` before every Play upload (Play rejects a re-used code).
The `~/.android/debug.keystore` is auto-generated per machine — nothing to carry for debug installs.

## Store listing (Play Console — separate from the on-device icon)

In Play Console / the store the app shows as `com.hopae.axle.wallet (unreviewed)` **with no icon or name**
until you fill the **store listing** — this is normal, and different from the on-device icon:

- **Launcher icon + label** ("Axle Wallet") come from the **AAB manifest** — already correct on installed
  devices, independent of Play.
- **Store listing** is set separately in **Grow → Store presence → Main store listing**: the store **app
  name**, a **512×512 PNG icon** (not the adaptive vector — a raster is required), a feature graphic
  (1024×500), screenshots, and a description.
- **“(unreviewed)”** just means the app is only on an internal-testing track (not published/reviewed) —
  expected, and **not required** for internal testing to work.

So fill the store listing only when you want the app to look complete inside Play; testers already see the
real Axle icon on their devices.

## What we did / verified

1. Rebranded to **Axle Wallet** (`com.hopae.axle.wallet`) with an EU-palette adaptive icon.
2. Generated an upload keystore (`CN=Axle Wallet`), added the release `signingConfig`, built a **signed AAB**.
3. Created the Play Console app, uploaded to **internal testing**, added a tester, installed **via Play**.
4. Play Integrity verdict for the Play-installed build (`installerPackageName = com.android.vending`):
   **`appIntegrity: PLAY_RECOGNIZED`**, **`appLicensingVerdict: LICENSED`**, `deviceIntegrity:
   MEETS_DEVICE_INTEGRITY`. (For comparison, the side-loaded debug build was `UNRECOGNIZED_VERSION` /
   `UNEVALUATED`.) See [`../wallet-provider/PLAY-INTEGRITY.md`](../wallet-provider/PLAY-INTEGRITY.md) §6–7.
