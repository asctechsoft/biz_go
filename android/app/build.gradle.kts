plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.asc.bizgo"
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
        applicationId = "com.asc.bizgo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // local_auth + flutter_secure_storage yêu cầu tối thiểu API 23.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        multiDexEnabled = true
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Engine debug nhét kèm lớp validation Vulkan 15.25MB. Nó CHỈ được nạp khi
    // chạy với cờ `--enable-vulkan-validation`, app này không dùng.
    //
    // ĐO THỰC TẾ: gỡ nó bỏ đúng 15.25MB nội dung khỏi archive, NHƯNG file .apk
    // trên đĩa gần như không đổi (165.321.799 → 165.321.707 byte) vì APK debug
    // vốn đã dư rất nhiều khoảng đệm. Giữ lại vì bớt được mã native vô ích khi
    // cài lên máy; đừng kỳ vọng .apk nhẹ đi. Cần soi lỗi Vulkan thì xoá khối này.
    packaging {
        jniLibs {
            excludes += "**/libVkLayer_khronos_validation.so"
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

flutter {
    source = "../.."
}
