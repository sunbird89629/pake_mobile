import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名的密钥信息放在 workspace 之外的 `~/.pake/signing.properties`。
// 两个位置都不能放：workspace 里的文件每次构建都被 syncTemplate 覆写；
// 仓库里则等于把私钥和口令提交上去。这个固定路径既活得过构建，也不进 git。
//
// 文件缺失时回落到 debug 签名——没配密钥的人仍然能出包自测。但回落是静默的
// 危险来源：debug 签名的包换台机器构建就装不上（签名指纹不同）。所以
// `pakem build` 会把实际用的签名类型打进结果里，见 androidSigningMode。
val pakeSigningProps = Properties().apply {
    val file = File(System.getProperty("user.home"), ".pake/signing.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val pakeHasReleaseKey = !pakeSigningProps.getProperty("storeFile").isNullOrBlank()

android {
    namespace = "com.example.pake_shell"
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
        applicationId = "com.example.pake_shell"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (pakeHasReleaseKey) {
            create("release") {
                // storeFile 写绝对路径；`file()` 对绝对路径是恒等的，
                // 对相对路径才会按 app 模块目录解析。
                storeFile = file(pakeSigningProps.getProperty("storeFile"))
                storePassword = pakeSigningProps.getProperty("storePassword")
                keyAlias = pakeSigningProps.getProperty("keyAlias")
                keyPassword = pakeSigningProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (pakeHasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
