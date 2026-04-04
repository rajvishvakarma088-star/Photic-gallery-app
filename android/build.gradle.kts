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

    afterEvaluate {
        if (project.hasProperty("android")) {
            val extension = project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
            val currentSdk = extension.compileSdkVersion
            if (currentSdk != null) {
                try {
                    val versionString = currentSdk.replace("android-", "")
                    val versionInt = versionString.toIntOrNull()
                    if (versionInt != null && versionInt < 31) {
                        extension.compileSdkVersion(36)
                        extension.buildToolsVersion("36.0.0")
                    }
                } catch (e: Exception) {
                    // Ignore parsing errors
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
