import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseKeyAlias = keystoreProperties.getProperty("keyAlias")
val releaseKeyPassword = keystoreProperties.getProperty("keyPassword")
val releaseStoreFile = keystoreProperties.getProperty("storeFile")
val releaseStorePassword = keystoreProperties.getProperty("storePassword")
val releaseSigningConfigured = !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank() &&
    !releaseStoreFile.isNullOrBlank() &&
    !releaseStorePassword.isNullOrBlank() &&
    rootProject.file(releaseStoreFile).exists()

android {
    namespace = "com.studyapp.study_app_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.studyapp.study_app_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keyAliasProp = keystoreProperties.getProperty("keyAlias")
            val keyPasswordProp = keystoreProperties.getProperty("keyPassword")
            val storeFileProp = keystoreProperties.getProperty("storeFile")
            val storePasswordProp = keystoreProperties.getProperty("storePassword")

            if (releaseSigningConfigured) {
                keyAlias = keyAliasProp
                keyPassword = keyPasswordProp
                storeFile = rootProject.file(storeFileProp)
                storePassword = storePasswordProp
            }
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        release {
            signingConfig = if (releaseSigningConfigured) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            manifestPlaceholders["usesCleartextTraffic"] = "false"
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
