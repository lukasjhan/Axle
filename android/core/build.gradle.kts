plugins {
    id("com.android.library")
}

group = "com.hopae.eudi.android"
version = "0.0.1-SNAPSHOT"

android {
    namespace = "com.hopae.eudi.wallet.android"
    compileSdk = 36

    defaultConfig {
        minSdk = 29
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    // SDK ports these adapters implement (wallet-api transitively exposes cbor for the keystore adapter).
    api("com.hopae.eudi:wallet-api:0.0.1-SNAPSHOT")
    api("com.hopae.eudi:txlog:0.0.1-SNAPSHOT")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Instrumented tests: real Android Key Attestation needs the device Keystore/TEE.
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
