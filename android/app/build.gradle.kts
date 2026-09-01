import java.util.Properties

// The release signing material, kept out of the source tree.
//
// Android identifies an app by the certificate it was signed with: a build
// signed with the debug key -- which is what this did -- can never be replaced
// by a properly signed one on a phone that already has it, and Play will not
// take it at all. The keystore and its passwords live in android/key.properties
// and android/verna-release.jks, both gitignored.
//
// Absent on a machine that has never signed a release, in which case the
// release build falls back to the debug key and says so.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ir.vernaservice.vpn"
    compileSdk = flutter.compileSdkVersion
    // jni_flutter, shared_preferences_android and url_launcher_android all
    // declare NDK 28.2.13676358, and Gradle prints a mismatch warning about it.
    // It is only a warning: the build proceeds, and 28.0 is what those plugins
    // were actually compiled against here. Staying on the version that is
    // already installed avoids a multi-GB NDK download. Revisit if a plugin
    // ever fails to link -- then install 28.2.13676358 and bump this.
    ndkVersion = "28.0.13004108"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        jniLibs {
            // flutter_v2ray does not just load libtun2socks.so -- it exec()s it
            // as a separate process. Modern Android keeps native libraries
            // compressed inside the APK and maps them straight from there, so
            // no such file exists on disk and ProcessBuilder.start() fails with
            // "error=2, No such file or directory".
            //
            // The tunnel then looks perfectly healthy and carries nothing: the
            // TUN interface comes up, the service reports CONNECTED, the core's
            // own latency probe passes (it runs in-process, no exec involved),
            // and every single connection times out because the one component
            // that moves packets between the interface and the proxy never
            // started. Measured on 2026-08-20: 0 of 20 configs carried traffic.
            //
            // Legacy packaging extracts the .so files at install time, which is
            // what makes them executable.
            useLegacyPackaging = true
        }
    }

    defaultConfig {
        applicationId = "ir.vernaservice.vpn"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val store = keystoreProperties["storeFile"] as String?
            if (store != null) {
                storeFile = rootProject.file(store)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties["storeFile"] != null) {
                signingConfigs.getByName("release")
            } else {
                // No keystore on this machine. The build still runs so the app
                // can be tried in release mode, but the result is not
                // distributable -- and the log says which key was used rather
                // than leaving it to be discovered later.
                logger.warn("verna: no key.properties -- signing release with the DEBUG key")
                signingConfigs.getByName("debug")
            }
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
