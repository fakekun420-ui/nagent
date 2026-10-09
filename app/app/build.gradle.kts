plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
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
            // -P de Gradle o -D del sistema (CI usa -P; local puede usar -D).
            fun prop(n: String): String? = (project.findProperty(n) as? String) ?: System.getProperty(n)
            storeFile = file(prop("nagentKs") ?: "nagent.keystore")
            storePassword = prop("nagentKsPass")
            keyAlias = prop("nagentKeyAlias")
            keyPassword = prop("nagentKeyPass")
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
