plugins {
    id("com.android.library")
}

group = "com.hopae.eudi.android"
version = "0.0.1-SNAPSHOT"

android {
    namespace = "com.hopae.eudi.wallet.android.attestation"
    compileSdk = 36

    defaultConfig {
        minSdk = 29
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    // The WalletAttestationProvider port + SecureArea/Http ports this reference adapter composes.
    api("com.hopae.eudi:wallet-api:0.0.1-SNAPSHOT")
    // JOSE (JWS signing of the instance-key PoP, JWK encoding, JSON) — no Android APIs, pure Kotlin.
    implementation("com.hopae.eudi:sdjwt:0.0.1-SNAPSHOT")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // Google Play Integrity API (real device/app integrity) + Task<>.await() interop.
    implementation("com.google.android.play:integrity:1.4.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")

    // Gated integration test against a locally-running wallet-provider (EUDI_WP_LIVE).
    testImplementation("com.hopae.eudi:testkit:0.0.1-SNAPSHOT")
    testImplementation("com.hopae.eudi:sdjwt:0.0.1-SNAPSHOT")
    testImplementation("junit:junit:4.13.2")
}
