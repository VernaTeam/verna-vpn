pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
    // Direct repositories first. Gradle only falls through to the next
    // repository on a 404, never on a network error, so a flaky mirror in front
    // fails the whole build. The aliyun mirrors stay as a fallback for when the
    // direct hosts are unreachable.
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // Flutter's own engine artifacts, from the mirror that is reachable
        // here. The debug engine was already in the Gradle cache, so this only
        // showed up on the first release build:
        //
        //   Could not resolve io.flutter:armeabi_v7a_release:1.0.0-77e2e947...
        //
        // The Flutter plugin adds download.flutter.io on storage.googleapis.com,
        // which does not answer from this connection.
        maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
}

// NOTE: deliberately no `dependencyResolutionManagement` block here. With
// RepositoriesMode.PREFER_SETTINGS, Gradle ignores repositories declared by
// projects -- including the Flutter engine repository that the Flutter Gradle
// Plugin injects from FLUTTER_STORAGE_BASE_URL. That made every `io.flutter:*`
// artifact unresolvable. Dependency repositories live in build.gradle.kts.

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}
include(":app")
