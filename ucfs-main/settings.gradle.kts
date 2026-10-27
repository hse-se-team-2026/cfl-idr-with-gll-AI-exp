// Standalone build of cfl-idr-with-gll against UCFS-AI-dev (org.ucfs:solver); see build.gradle.kts.
// It is not included in the root build: the two builds use different Kotlin plugins (1.9.20 and 2.4.0).
plugins {
	id("org.gradle.toolchains.foojay-resolver-convention") version "0.8.0"
}
rootProject.name = "cfl-idr-with-gll"
