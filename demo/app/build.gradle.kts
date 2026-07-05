plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.hopae.eudi.demo"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.hopae.eudi.demo"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
    }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        getByName("debug") { isMinifyEnabled = false }
    }
}

dependencies {
    // EUDI Wallet SDK (via composite build ../kotlin)
    implementation("com.hopae.eudi:wallet:0.0.1-SNAPSHOT")
    implementation("com.hopae.eudi:wallet-api:0.0.1-SNAPSHOT")
    // debug-grade software SecureArea + in-memory helpers
    implementation("com.hopae.eudi:testkit:0.0.1-SNAPSHOT")

    // Jetpack Compose
    implementation(platform("androidx.compose:compose-bom:2024.09.03"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // QR scanning (camera)
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")

    // Digital Credentials API (Credential Manager provider) — OpenID4VP registry + bundled matcher
    implementation("androidx.credentials:credentials:1.5.0")
    implementation("androidx.credentials.registry:registry-provider:1.0.0-alpha04")
    implementation("androidx.credentials.registry:registry-provider-play-services:1.0.0-alpha04")
    implementation("androidx.credentials.registry:registry-digitalcredentials-openid:1.0.0-alpha04")
    implementation("androidx.credentials.registry:registry-digitalcredentials-mdoc:1.0.0-alpha04")
    implementation("androidx.credentials.registry:registry-digitalcredentials-sdjwtvc:1.0.0-alpha04")
}
