plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")      // ✅ 최신 표기 (kotlin-android → org.jetbrains.kotlin.android)
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")    // ✅ Google Services 플러그인 적용 (settings.gradle.kts에 버전 선언되어 있어야 함)
}

android {
    namespace = "com.example.charcoal_order_app"   // ✅ 실제 패키지명 유지
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // ✅ AGP 8.x는 JDK 17 권장
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.charcoal_order_app" // ✅ Firebase 콘솔 등록값과 동일해야 함
        minSdk = flutter.minSdkVersion   // (21 이상이면 OK)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: 실제 배포 시 서명 키 설정 필요
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Firebase BOM으로 버전 일괄 관리
    implementation(platform("com.google.firebase:firebase-bom:34.0.0"))

    // ✅ 원하는 모듈만 추가
    implementation("com.google.firebase:firebase-analytics")
    // implementation("com.google.firebase:firebase-auth")
    // implementation("com.google.firebase:firebase-firestore")
}

