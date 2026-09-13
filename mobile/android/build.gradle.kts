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

    // Pin every plugin module to compileSdk 37.0.
    //
    // Several plugins (permission_handler_android, flutter_secure_storage)
    // declare compileSdk 37 in their AAR metadata. A bare `compileSdk = 37`
    // resolves to the platform hash "android-37", which does not exist: the
    // SDK ships "platforms;android-37.0", reporting AndroidVersion.ApiLevel
    // 37.0. Without the minor component the build fails with
    //
    //     Failed to find target with hash string 'android-37'
    //
    // and pinning everything down to 36 instead fails the AAR metadata check.
    // Declaring the minor explicitly resolves to "android-37.0" and satisfies
    // both.
    //
    // Configured through plugins.withId rather than afterEvaluate, because the
    // evaluationDependsOn(":app") below forces subprojects to evaluate first
    // and an afterEvaluate hook registered here would arrive too late.
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            compileSdk = 37
            compileSdkMinor = 0
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
