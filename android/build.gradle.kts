allprojects {
    // Direct repositories first; the aliyun mirrors are only a fallback. Gradle
    // aborts the build on a network error instead of trying the next repository,
    // so a flaky mirror in front is worse than no mirror at all.
    repositories {
        google()
        mavenCentral()
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
    }
}

// Force every module onto an SDK platform that is actually installed.
//
// The `jni` / `jni_flutter` packages (pulled in transitively by the Flutter
// plugins) hardcode `compileSdk 35` in their own build files. Gradle then tries
// to install platform 35 from dl.google.com, which is geo-blocked here: the
// download hangs for hours and finally fails, leaving an empty android-35
// directory behind. Platform 36 is installed and API-compatible for these
// modules, so we raise anything below 36 up to 36.
//
// Reflection is deliberate: the typed `BaseExtension` accessor is deprecated in
// AGP 9 and referencing it turns the build script into a compile error.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            runCatching {
                val getter = androidExt.javaClass.methods.first { it.name == "getCompileSdk" }
                val current = getter.invoke(androidExt) as? Int
                if (current != null && current < 36) {
                    val setter = androidExt.javaClass.methods.first {
                        it.name == "setCompileSdk" && it.parameterCount == 1
                    }
                    setter.invoke(androidExt, 36)
                    logger.lifecycle("Raised ${project.path} compileSdk $current -> 36")
                }
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
