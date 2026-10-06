plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.randil.randil_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.randil.randil_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // MACHINE WORKAROUND (this laptop only): every LLVM-built Android tool
        // (SDK cmake/ninja, NDK clang/llvm-strip/aapt2/...) crashes at launch
        // with a stack overflow (0xC00000FD) on this Windows build. These
        // CMake cache seeds tell CMake the compiler is Clang and already
        // probed, so the configure run never needs to execute the broken
        // clang. Only active when -P/gradle.properties randil.machineWorkaround
        // is "true"; skipped on healthy machines (e.g. CI).
        if (project.findProperty("randil.machineWorkaround") == "true") {
            externalNativeBuild {
                cmake {
                    arguments(
                        "-DCMAKE_C_COMPILER_ID=Clang",
                        "-DCMAKE_CXX_COMPILER_ID=Clang",
                        "-DCMAKE_C_COMPILER_WORKS=ON",
                        "-DCMAKE_CXX_COMPILER_WORKS=ON",
                        "-DCMAKE_C_ABI_COMPILED=ON",
                        "-DCMAKE_CXX_ABI_COMPILED=ON",
                        "-DCMAKE_C_SIZEOF_DATA_PTR=8",
                        "-DCMAKE_CXX_SIZEOF_DATA_PTR=8",
                        "-DCMAKE_C_COMPILER_FORCED=TRUE",
                        "-DCMAKE_CXX_COMPILER_FORCED=TRUE"
                    )
                }
            }
        }
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

// MACHINE WORKAROUND (this laptop only): NDK llvm-strip crashes (0xC00000FD)
// on this Windows build. The strip step only shrinks the APK by removing debug
// symbols — skipping it leaves the APK slightly larger but fully working.
// Only active when the randil.machineWorkaround property is "true".
if (project.findProperty("randil.machineWorkaround") == "true") {
    tasks.whenTaskAdded {
        if (name.startsWith("strip") && name.endsWith("DebugSymbols")) {
            enabled = false
        }
    }
}