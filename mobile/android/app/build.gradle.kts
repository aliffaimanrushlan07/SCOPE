import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The Google Maps Android key is read from android/local.properties, which is
// gitignored, and injected into the manifest as a placeholder at build time.
//
// It is NOT written into AndroidManifest.xml directly, because that file is
// committed — a key pasted there would be published to GitHub the moment the
// repository is pushed. The key still ships inside the APK and can be
// extracted from it; that is unavoidable for the Maps SDK, and is why the key
// is restricted by package name and signing certificate in the Cloud console.
val mapsApiKey: String = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}.getProperty("MAPS_API_KEY") ?: ""

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

        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
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
