allprojects {
    repositories {
        maven { url = uri("https://developer.huawei.com/repo/") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
//        google()
//        mavenCentral()
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
subprojects {
    // Use the same NDK as the app (Flutter 3.47.6) for native Flutter plugins.
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            ndkVersion = "28.2.13676358"
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    // Flutter integration_test uses dynamic versions (1.2+/3.3+). Pin its
    // Android test stack so APK builds do not depend on mirror metadata queries.
    configurations.configureEach {
        resolutionStrategy.force(
            "androidx.test:runner:1.3.0",
            "androidx.test:rules:1.2.0",
            "androidx.test.espresso:espresso-core:3.3.0",
        )
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
