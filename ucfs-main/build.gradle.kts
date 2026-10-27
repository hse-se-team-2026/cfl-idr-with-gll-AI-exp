// Standalone build: the unchanged main code of cfl-idr-with-gll (../src/main/kotlin) compiled against
// UCFS-AI-dev (org.ucfs:solver, the UCFS that Qilin uses), tested with the repository's tests and
// published as org.cfl_idr_with_gll:cfl-idr-with-gll for Qilin.
//
// Why a separate build and not a change of the root one:
// - the root build compiles against libs/solver-new.jar (UCFS PR #50), whose SPPF API differs from
//   UCFS-AI-dev (RangeSppfNode is abstract there and `children` is an Iterable; in UCFS-AI-dev it is a
//   data class with an ArrayList), so the same sources give different bytecode;
// - org.ucfs:solver and its kotlin-stdlib carry Kotlin 2.4 metadata, which the root Kotlin 1.9.20
//   compiler cannot read (E1-S5 V1), so this build uses Kotlin 2.4.0; one Gradle build cannot hold
//   both Kotlin plugins.
//
// The four SPPF fixtures utils/sppfForExtractEdges/** and their test TestExtractEdgesFromSppfResult
// build SPPF nodes of PR #50 (BinarySppfNode, LeafSppfNode, ...) that UCFS-AI-dev does not have
// (E1-S5 V2), so they are not compiled here; every other test of the repository runs unchanged.
//
// Usage (from the repository root, JDK 21):
//   ./gradlew -p ucfs-main -PucfsRepo=<maven repo with org.ucfs:solver> test publishLibPublicationToMavenLocal \
//       -Dmaven.repo.local=<dir>
// Properties: ucfsRepo (required; org.ucfs is resolved only from it), ucfsVersion (default 0.1.0-ai-SNAPSHOT).
import java.util.jar.JarFile

plugins {
	kotlin("jvm") version "2.4.0"
	`java-library`
	`maven-publish`
}

group = "org.cfl_idr_with_gll"
version = "0.1.0-ai-SNAPSHOT"

val repoRoot: File = projectDir.parentFile

val ucfsRepo: String = providers.gradleProperty("ucfsRepo").orNull?.takeIf { it.isNotBlank() }
	?: throw GradleException("ucfs-main: pass -PucfsRepo=<maven repository with org.ucfs:solver>")
val ucfsVersion: String = providers.gradleProperty("ucfsVersion").getOrElse("0.1.0-ai-SNAPSHOT")

repositories {
	exclusiveContent {
		forRepository {
			maven {
				name = "ucfs"
				url = uri(ucfsRepo)
			}
		}
		filter { includeGroup("org.ucfs") }
	}
	mavenCentral()
}

dependencies {
	// logback is the solver's own logging backend; a library must not force one on its users (Qilin).
	api("org.ucfs:solver:$ucfsVersion") {
		exclude(group = "ch.qos.logback")
	}
	implementation("org.jgrapht:jgrapht-core:1.5.2")
	testImplementation(kotlin("test"))
}

kotlin {
	jvmToolchain(21)
	sourceSets {
		named("main") {
			kotlin.setSrcDirs(listOf(repoRoot.resolve("src/main/kotlin")))
		}
		named("test") {
			kotlin.setSrcDirs(listOf(repoRoot.resolve("src/test/kotlin")))
			kotlin.exclude("utils/sppfForExtractEdges/**", "utils/TestExtractEdgesFromSppfResult.kt")
		}
	}
}

sourceSets {
	main { resources.setSrcDirs(listOf(repoRoot.resolve("src/main/resources"))) }
	test { resources.setSrcDirs(listOf(repoRoot.resolve("src/test/resources"))) }
}

tasks.test {
	useJUnitPlatform()
	// The correctness tests read graphs by paths relative to the repository root (src/test/resources/...).
	workingDir = repoRoot
}

// Git state of the cfl-idr sources this jar is built from.
fun git(vararg args: String): String? = try {
	val result = providers.exec {
		workingDir = repoRoot
		commandLine("git", *args)
		isIgnoreExitValue = true
	}
	if (result.result.get().exitValue == 0) result.standardOutput.asText.get().trim() else null
} catch (e: Exception) {
	null
}

val cflIdrCommit: String = git("rev-parse", "HEAD") ?: "unknown"
val cflIdrDirty: String = git("status", "--porcelain", "--", "src/main", "ucfs-main")
	?.let { it.isNotEmpty().toString() } ?: "unknown"

// The solver jar this build compiles against; UCFS-Commit is read from its manifest, so it names the
// UCFS that was actually used, whatever repository or version was passed.
val ucfsSolverJar: Provider<File> = configurations.compileClasspath.map { cp ->
	cp.incoming.artifactView {
		componentFilter { id ->
			id is ModuleComponentIdentifier && id.group == "org.ucfs" && id.module == "solver"
		}
	}.files.singleFile
}

tasks.jar {
	val solverJar = ucfsSolverJar
	inputs.file(solverJar).withPropertyName("ucfsSolverJar")
	manifest {
		attributes(
			"Implementation-Title" to "cfl-idr-with-gll",
			"Implementation-Version" to project.version.toString(),
			"CflIdr-Commit" to cflIdrCommit,
			"CflIdr-Dirty" to cflIdrDirty,
		)
	}
	doFirst {
		val solverAttributes = JarFile(solverJar.get()).use { it.manifest?.mainAttributes }
		val ucfsCommit = solverAttributes?.getValue("UCFS-Commit")
			?: throw GradleException("no UCFS-Commit in the manifest of ${solverJar.get()}")
		manifest.attributes(
			"UCFS-Commit" to ucfsCommit,
			"UCFS-Dirty" to (solverAttributes.getValue("UCFS-Dirty") ?: "unknown"),
		)
	}
}

publishing {
	publications {
		create<MavenPublication>("lib") {
			groupId = "org.cfl_idr_with_gll"
			artifactId = "cfl-idr-with-gll"
			version = project.version.toString()
			from(components["java"])
		}
	}
}

// With `test publish...` in one invocation, a failing test stops the build before anything is published.
tasks.withType<AbstractPublishToMaven>().configureEach {
	mustRunAfter(tasks.test)
}
