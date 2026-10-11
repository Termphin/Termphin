import java.util.Properties
import java.io.FileInputStream

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

android {
    namespace = "dev.termphin.termphin"
    // flutter_secure_storage 11 requires SDK 37, ahead of this Flutter
    // version's own default - pinned explicitly until the tooling catches up.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        // Off by default from AGP 9. The build type overrides app_name with
        // it, which is what keeps a debug install labelled as one.
        resValues = true
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.termphin.termphin"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        // Ahead of this Flutter version's default of 36. What API 37 turns on:
        // ACCESS_LOCAL_NETWORK is enforced (see LocalNetworkChannel.kt), and
        // orientation/aspect-ratio restrictions are ignored above sw600dp -
        // which costs nothing here, the app neither locks orientation nor
        // declares an aspect ratio.
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { project.file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
        getByName("debug") {
            keyAlias = "androiddebugkey"
            keyPassword = "android"
            storeFile = file("debug-keystore.jks")
            storePassword = "android"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
            applicationIdSuffix = ".debug"
            resValue("string", "app_name", "Termphin Debug")
        }
        release {
            signingConfig = signingConfigs.getByName(
                if (keystorePropertiesFile.exists()) "release" else "debug",
            )
            resValue("string", "app_name", "Termphin")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

    kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

android.packaging {
    resources {
        excludes += "META-INF/versions/**/OSGI-INF/MANIFEST.MF"
        excludes += "META-INF/DEPENDENCIES"
        excludes += "META-INF/LICENSE"
        excludes += "META-INF/NOTICE"
        excludes += "META-INF/*.SF"
        excludes += "META-INF/*.DSA"
        excludes += "META-INF/*.RSA"
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
