plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "my.edu.scope"
    // 37.0, not a bare 37: the installed platform reports
    // AndroidVersion.ApiLevel=37.0 and a bare 37 resolves to the
    // non-existent hash "android-37". See android/build.gradle.kts.
    compileSdk = 37
    compileSdkMinor = 0
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "my.edu.scope"

        // Android 10. Pinned here rather than inherited from
        // flutter.minSdkVersion so the build matches the minimum stated in the
        // project's hardware requirements, and so a dependency bump cannot
        // raise it without the change being visible in this file.
        minSdk = 29

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
