import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, kept out of the repository.
//
// Copy `key.properties.example` to `android/key.properties` and point it at
// your keystore. Play will not accept a build signed with the debug key, and
// once an app is published the upload key can never be changed without
// Google's key-reset process — so this has to be a real key from the first
// upload, not something to sort out later.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.driverwealthos.driver_wealth_os"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.driverwealthos.driver_wealth_os"
        // 26 (Oreo) is the floor for the background-location and
        // foreground-service behaviour the mileage tracker depends on.
        minSdk = 26
        // Pinned rather than inherited from the Flutter SDK. Android changes
        // foreground-service and notification rules between API levels, and
        // the mileage tracker depends on both — a silent bump on a Flutter
        // upgrade could change tracking behaviour with no code change.
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Falling back keeps `flutter run --release` working on a
                // machine with no keystore. The warning is here because the
                // failure mode is otherwise invisible: the build succeeds and
                // produces an artifact Play silently refuses.
                logger.warn(
                    "WARNING: android/key.properties not found — signing the " +
                        "release build with debug keys. This artifact cannot " +
                        "be uploaded to Google Play."
                )
                signingConfig = signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
