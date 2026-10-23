import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun signingValue(propertyName: String, environmentName: String): String? =
    keystoreProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }
        ?: System.getenv(environmentName)?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
val hasReleaseSigningConfig = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.cbv.filehub"
    // flutter.compileSdkVersion is still 36; flutter_secure_storage 11 and
    // permission_handler_android 14 both compile against 37.
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = System.getenv("ANDROID_APPLICATION_ID")?.takeIf { it.isNotBlank() }
            ?: "com.cbv.filehub"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        externalNativeBuild {
            cmake {
                // Match the existing packaging exclusion without setting NDK
                // filters, which conflict with Flutter's split-per-ABI builds.
                abiFilters += listOf("arm64-v8a", "x86_64")
                arguments += listOf(
                    "-DANDROID_STL=c++_static",
                    "-DCB_LLAMA_PACKAGE_ROOT=${layout.buildDirectory.dir("generated/llamaJniLibs").get().asFile.invariantSeparatorsPath}",
                )
                targets += "llama-server"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    sourceSets {
        getByName("debug").jniLibs.srcDir(layout.buildDirectory.dir("generated/llamaJniLibs/debug"))
        getByName("profile").jniLibs.srcDir(layout.buildDirectory.dir("generated/llamaJniLibs/profile"))
        getByName("release").jniLibs.srcDir(layout.buildDirectory.dir("generated/llamaJniLibs/release"))
    }

    packaging {
        jniLibs {
            excludes += "**/armeabi-v7a/**"
            // Process.start needs the executable in nativeLibraryDir. Executing
            // a binary copied into writable app storage is blocked on Android 10+.
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (hasReleaseSigningConfig) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Executables are not collected as shared libraries by AGP. Build them before
// AGP reads the generated jniLibs source directories for APK/AAB packaging.
tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("JniLibFolders")) {
        val variant = name.removePrefix("merge").removeSuffix("JniLibFolders")
        dependsOn("externalNativeBuild$variant")
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Native player for PiP (Media3 ExoPlayer)
    implementation("androidx.media3:media3-exoplayer:1.3.1")
    implementation("androidx.media3:media3-ui:1.3.1")
}
