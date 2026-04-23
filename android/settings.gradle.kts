pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "EclipseAndroid"

include(
    ":app",
    ":core:design",
    ":core:model",
    ":core:network",
    ":core:storage",
    ":core:player",
    ":core:js",
    ":feature:home",
    ":feature:search",
    ":feature:detail",
    ":feature:schedule",
    ":feature:services",
    ":feature:library",
    ":feature:downloads",
    ":feature:settings",
    ":feature:manga",
    ":feature:novel",
)

