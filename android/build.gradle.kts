allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// `audioplayers_android` 5.3.0 dùng khối `kotlin { compilerOptions {...} }`
// (build.gradle:57) nhưng quên `apply plugin: 'kotlin-android'`, lại còn ghim
// KGP 1.7.10 trong buildscript riêng — bản đó chưa có DSL `kotlin {}` cho
// Android. Kết quả: "Could not find method kotlin()".
// Vá ở đây (không sửa pub cache — `pub get` sẽ xoá và hỏng mọi project khác):
// ép KGP mới cho classpath của plugin, rồi apply Kotlin ngay khi AGP vừa được
// apply (dòng 27) để khối `kotlin {}` ở dòng 57 có extension mà chạy.
subprojects {
    if (name == "audioplayers_android") {
        buildscript {
            configurations.all {
                resolutionStrategy.eachDependency {
                    if (requested.group == "org.jetbrains.kotlin" &&
                        requested.name == "kotlin-gradle-plugin"
                    ) {
                        useVersion("2.2.20")
                    }
                }
            }
        }
        plugins.withId("com.android.library") {
            apply(plugin = "org.jetbrains.kotlin.android")
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
