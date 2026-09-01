plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.grooveforge.grooveforge"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.grooveforge.grooveforge"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26 // AAudio (API 26) required for low-latency GFPA effects on keyboard audio
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Check if we are in CI or have a local signing config
            val keystoreFile = project.file("release-keystore.jks")
            if (keystoreFile.exists()) {
                println("GrooveForge: Using release keystore at ${keystoreFile.absolutePath}")
                signingConfigs.create("release") {
                    storeFile = keystoreFile
                    storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                    keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                    keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
                }
                signingConfig = signingConfigs.getByName("release")
            } else {
                println("GrooveForge: WARNING: Release keystore not found at ${keystoreFile.absolutePath}, falling back to debug.")
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }

    applicationVariants.all {
        outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            output.outputFileName = "GrooveForge_${flutter.versionName}.apk"
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../native_audio/CMakeLists.txt")
        }
    }

    packaging {
        jniLibs {
            // androidx.datastore (pulled in by shared_preferences_android) ships
            // libdatastore_shared_counter.so built with NDK r20 — still true as of
            // datastore 1.3.0-alpha10. The .so is 16 KB aligned, but Play flags the
            // old NDK stamp as a 16 KB page-size crash risk.
            //
            // That counter is only used by MultiProcessCoordinator. shared_preferences
            // uses `preferencesDataStore`, i.e. SingleProcessCoordinator, which never
            // references SharedCounter, so the library is never loaded and dropping it
            // is a no-op at runtime. Revisit if anything ever adopts MultiProcessDataStore.
            excludes += "**/libdatastore_shared_counter.so"
        }
    }
}

flutter {
    source = "../.."
}
