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
        minSdk = flutter.minSdkVersion
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
}

flutter {
    source = "../.."
}
