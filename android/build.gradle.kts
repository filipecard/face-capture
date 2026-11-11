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
// Força o NDK já instalado nesta máquina em todos os módulos (ex.: plugin
// `jni`, que fixa `flutter.ndkVersion` = 28.2 e dispararia um download).
// Para usar o NDK padrão do Flutter, remova este bloco e o ndkVersion do app.
val labNdkVersion = "29.0.14206865"
subprojects {
    val forceNdk = {
        extensions.findByName("android")?.withGroovyBuilder {
            setProperty("ndkVersion", labNdkVersion)
        }
    }
    if (state.executed) forceNdk() else afterEvaluate { forceNdk() }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
