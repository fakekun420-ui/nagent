plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.nagent.app"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.nagent.app"
        minSdk = 28
        targetSdk = 34
        versionCode = 100
        versionName = "0.1.0"
    }
    signingConfigs {
        create("proyecto") {
            storeFile = file(System.getProperty("nagentKs") ?: "nagent.keystore")
            storePassword = System.getProperty("nagentKsPass")
            keyAlias = System.getProperty("nagentKeyAlias")
            keyPassword = System.getProperty("nagentKeyPass")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("proyecto")
            isMinifyEnabled = true
        }
        debug {
            applicationIdSuffix = ".debug"
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}
dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.ui:ui:1.7.0")
    implementation("androidx.compose.material3:material3:1.2.1")
}
