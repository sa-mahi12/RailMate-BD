plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "bd.railmate.railmate_bd"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "bd.railmate.railmate_bd"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // P28: real release signing. The keystore and its passwords are supplied
    // ONLY through environment variables (populated from GitHub Secrets on the
    // CI runner, or from the owner's shell locally). Nothing secret is
    // committed: no keystore file, no key.properties, no literal password.
    //
    // When the four RAILMATE_* variables are absent (e.g. a contributor
    // running `flutter run --release` locally), the release build type falls
    // back to debug signing so the build still succeeds — CI, which always
    // sets them, produces the genuinely signed artifact.
    // NOTE: the local names deliberately do NOT match the SigningConfig
    // property names (`keyAlias`, `keyPassword`, ...). In Kotlin DSL a
    // `keyAlias = keyAlias` inside the signing-config scope resolves the left
    // side to this local `val` and fails to compile ("val cannot be
    // reassigned"), so the locals are prefixed.
    val signingKeystorePath = System.getenv("RAILMATE_KEYSTORE_PATH")
    val signingStorePassword = System.getenv("RAILMATE_KEYSTORE_PASSWORD")
    val signingKeyAlias = System.getenv("RAILMATE_KEY_ALIAS")
    val signingKeyPassword = System.getenv("RAILMATE_KEY_PASSWORD")
    val signingConfigured = signingKeystorePath != null &&
        signingStorePassword != null &&
        signingKeyAlias != null &&
        signingKeyPassword != null

    signingConfigs {
        if (signingConfigured) {
            create("release") {
                storeFile = file(signingKeystorePath!!)
                storePassword = signingStorePassword
                keyAlias = signingKeyAlias
                keyPassword = signingKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (signingConfigured) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "P28: release signing env vars missing; falling back to the " +
                        "debug key. The resulting APK is NOT the owner-facing " +
                        "release artifact. Set RAILMATE_KEYSTORE_PATH, " +
                        "RAILMATE_KEYSTORE_PASSWORD, RAILMATE_KEY_ALIAS and " +
                        "RAILMATE_KEY_PASSWORD (or the equivalent GitHub " +
                        "Secrets) for a signed release."
                )
                signingConfigs.getByName("debug")
            }
            // P28: no debuggable flag, no debug banner, minify off (the app has
            // no reflection-heavy hot paths that need R8 rules) but resource
            // shrinking kept off too so the demo build stays inspectable.
            isDebuggable = false
            isMinifyEnabled = false
            isShrinkResources = false
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
