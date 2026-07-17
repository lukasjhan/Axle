# Axle Wallet (iOS) — release & TestFlight distribution

How the iOS demo app is signed, archived, and handed to testers via **TestFlight** — the iOS counterpart of
the Android [`demo/RELEASE.md`](../demo/RELEASE.md) (Google Play internal testing). TestFlight **internal**
testing needs no App Review and publishes near-instantly, so it's the closest match to a Play internal track.

For the App Attest attestation the wallet sends at registration, see the DC API / adapter notes in
[`docs/` → iOS adapters](../docs/docs/guides/ios-adapters.mdx) and the backend `wallet-provider/`.

> Nothing secret is committed. The commands below reference values already public in the Xcode project
> (bundle IDs, Team ID); the App Store Connect **API key** and any built **archive/IPA** stay local
> (gitignored — see the end).

## App identity

- **App** `com.hopae.axle.wallet` · **Extension** `com.hopae.axle.wallet.idprovider` (embedded in the app,
  ships automatically). Team **`P3A48743C4`** (Hopae Inc.). Display name **“Axle Wallet”**.
- **Version / build** live in the target build settings: `MARKETING_VERSION` (e.g. `1.0`, user-facing) and
  `CURRENT_PROJECT_VERSION` (the build number — **must increase for every TestFlight upload**).
- The bundle ID is **permanent once the App Store Connect record exists** — it's the identity App Attest and
  the DC API entitlement are bound to.

## 1. Distribution signing

TestFlight needs an **App Store distribution** signing identity (the local *development* profile can't be
uploaded). Two ways:

- **Automatic (simplest).** In Xcode → target → *Signing & Capabilities*, keep *Automatically manage
  signing* with Team `P3A48743C4`. When you **Archive**, Xcode generates the App Store distribution
  certificate + provisioning profiles for **both** the app and the `.idprovider` extension on demand.
- **Manual.** Create an *Apple Distribution* certificate and *App Store* provisioning profiles for both
  bundle IDs in the [Developer portal](https://developer.apple.com/account/resources), then select them per
  target.

Either way the **distribution** profiles must carry the same capabilities as debug — App Groups, Keychain
Sharing, and the Apple-approved **`com.apple.developer.identity-document-services.document-provider.mobile-document-types`**
doctype entitlement on the app (already granted; confirm it survived signing with
`codesign -d --entitlements :- "Axle Wallet.app"`).

## 2. Create the app in App Store Connect

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps → +** → *New App*: platform iOS,
Bundle ID `com.hopae.axle.wallet`, an SKU, primary language. (One-time.)

## 3. Archive

**Xcode:** select *Any iOS Device (arm64)* → **Product → Archive**.

**CLI** (unattended / CI), archive then export with an `ExportOptions.plist`:

```sh
cd demo-ios/AxleWallet
xcodebuild -project AxleWallet.xcodeproj -scheme AxleWallet \
  -destination 'generic/platform=iOS' -archivePath build/AxleWallet.xcarchive \
  clean archive

# ExportOptions.plist (template — Team ID is public; keep any generated copy local):
#   <plist><dict>
#     <key>method</key><string>app-store-connect</string>
#     <key>teamID</key><string>P3A48743C4</string>
#     <key>uploadSymbols</key><true/>
#   </dict></plist>
xcodebuild -exportArchive -archivePath build/AxleWallet.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
```

## 4. Upload

- **Xcode Organizer:** *Window → Organizer → Archives → Distribute App → App Store Connect → Upload.*
- **CLI:** upload the exported `.ipa` with an **App Store Connect API key** (App Store Connect → *Users and
  Access → Integrations → App Store Connect API* → generate a key; download the `AuthKey_XXXX.p8` **once** and
  keep it local):
  ```sh
  xcrun altool --upload-app -f build/export/AxleWallet.ipa -t ios \
    --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID
  # (altool reads AuthKey_$ASC_KEY_ID.p8 from ~/.appstoreconnect/private_keys/ or ./private_keys/)
  ```
  Or `fastlane pilot upload` if you set up fastlane (optional; see below).

## 5. TestFlight — internal testing (no review)

App Store Connect → **TestFlight**. After the build finishes processing (a few minutes):

- **Internal testing** — add up to **100** App Store Connect team members as testers, assign the build. **No
  Beta App Review**; available almost immediately. *(The Play internal-track equivalent.)*
- **External testing** — up to **10,000** testers via public link / email; the first build needs a one-time
  lightweight **Beta App Review**.

Testers install through the **TestFlight app** on their device.

## Notes specific to this app

- **App Attest.** On a real device App Attest runs for real (not the `DevIntegrityTokenProvider` fallback,
  which is Simulator-only). A **local Xcode build** attests in Apple's **development** environment (authenticator
  `aaguid = appattestdevelop`); a **TestFlight / App Store** build attests in **production** (`aaguid = appattest`).
  The wallet-provider backend accepts **both**, so registration works in either — TestFlight additionally
  exercises the production App Attest path.
- **Export compliance.** To skip the encryption question on every upload, add
  `ITSAppUsesNonExemptEncryption` to `Info.plist` with the value that matches your compliance assessment (a
  wallet using only standard cryptography for authentication over HTTPS is typically **exempt** → `false`).
  This is a legal declaration — confirm it for your distribution.
- **iOS 26 only.** The deployment target is iOS 26 (the DC API needs it); testers need an iOS 26 device.

## Secrets (never committed)

Gitignored — generate/provide your own:

| Secret | What |
|---|---|
| `AuthKey_*.p8` | App Store Connect API key (upload auth) |
| `*.xcarchive`, `*.ipa` | build artifacts |
| `demo-ios/AxleWallet/AxleWallet/reader_wrpac.json` | Read-mDL reader-auth WRPAC (see the demo) |

The **App Store distribution certificate/profiles** are managed by Xcode automatic signing (or your portal
account) — they are per-team and not part of the repo.
