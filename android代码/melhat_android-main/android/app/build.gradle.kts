import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val splitApks = project.findProperty("split-per-abi")?.toString() == "true"
val requestedDebugAbis =
    (project.findProperty("target-platform")?.toString() ?: "android-arm64,android-x64")
        .split(",")
        .mapNotNull {
            when (it) {
                "android-arm" -> "armeabi-v7a"
                "android-arm64" -> "arm64-v8a"
                "android-x64" -> "x86_64"
                else -> null
            }
        }

android {
    namespace = "com.rolling.intelligence_headband"
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
        applicationId = "com.rolling.intelligence_headband"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Flutter's default includes 32-bit libraries even when its engine was
        // built only for 64-bit targets. Filter the same ABIs as the engine.
        ndk { abiFilters.clear() }
        val push = Properties().apply {
            val file = rootProject.file("push.properties")
            if (file.exists()) file.inputStream().use { load(it) }
        }
        manifestPlaceholders["JPUSH_PKGNAME"] = applicationId!!
        manifestPlaceholders["JPUSH_APPKEY"] = push.getProperty("JPUSH_APPKEY", "")
        manifestPlaceholders["JPUSH_CHANNEL"] = "wearable"
        manifestPlaceholders["WEAR_PUSH_VENDORS"] = push.getProperty("JPUSH_VENDORS", "")
        listOf("XIAOMI_APPID", "XIAOMI_APPKEY", "HUAWEI_APPID", "VIVO_APPID", "VIVO_APPKEY", "OPPO_APPID", "OPPO_APPKEY", "OPPO_APPSECRET", "HONOR_APPID").forEach {
            manifestPlaceholders[it] = push.getProperty(it, "")
        }
    }

    val signingFile = rootProject.file("signing.properties")
    val signing = Properties().apply {
        if (signingFile.exists()) signingFile.inputStream().use { load(it) }
    }
    signingConfigs {
        if (signingFile.exists()) {
            create("release") {
                storeFile = rootProject.file(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.findByName("release")
            ndk {
                abiFilters.clear()
                if (!splitApks) abiFilters.add("arm64-v8a")
            }
            // 修复 R8 跨盘符路径警告
            androidResources {
                additionalParameters += listOf("--no-version-vectors")
            }
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
            ndk {
                abiFilters.clear()
                if (!splitApks) abiFilters.addAll(requestedDebugAbis)
            }
        }
    }

    packaging {
        // dex {
        //    useLegacyPackaging = true
        // }
        // jniLibs {
        //    useLegacyPackaging = true
        // }
    }
}

flutter {
    source = "../.."
}

// Vendor channels are opt-in and must match the 6.2.0 native SDK in jpush_flutter 3.5.7.
val pushOptions = Properties().apply {
    val file = rootProject.file("push.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val pushVendors = pushOptions.getProperty("JPUSH_VENDORS", "").split(",").map { it.trim() }.filter { it.isNotEmpty() }
dependencies {
    pushVendors.forEach { vendor ->
        require(vendor in setOf("huawei", "xiaomi", "vivo", "oppo", "honor")) { "Unsupported push vendor: $vendor" }
        implementation("cn.jiguang.sdk.plugin:$vendor:6.2.0")
    }
    if (pushVendors.any { it in setOf("oppo", "honor") }) {
        implementation(fileTree(mapOf("dir" to "../vendor-libs", "include" to listOf("*.aar"))))
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        require(rootProject.file("signing.properties").exists()) { "Release requires android/signing.properties; debug signing is never used for release." }
        val defines = (project.findProperty("dart-defines") as? String).orEmpty()
            .split(",").filter { it.isNotEmpty() }
            .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
        val apiUrl = defines.firstOrNull { it.startsWith("API_BASE_URL=") }?.substringAfter("=")
        require(apiUrl?.startsWith("https://") == true) { "Release requires --dart-define=API_BASE_URL=https://your-authorized-server" }
        require("LEGACY_DEMO=true" !in defines) { "Release must not enable LEGACY_DEMO." }
    }
}
