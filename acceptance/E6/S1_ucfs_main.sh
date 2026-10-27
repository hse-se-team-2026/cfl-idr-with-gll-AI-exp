#!/usr/bin/env bash
# E6-S1 acceptance (cfl-idr-with-gll-AI-exp): the main code of cfl-idr-with-gll, unchanged, compiled
# against UCFS-AI-dev (org.ucfs:solver, the solver Qilin uses) by the standalone build ucfs-main/,
# tested with the repository's own tests and published as a Maven artifact for Qilin
# (docs/ai/tickets/E6-S1.md in the Diploma_work docs; plan: E6.md D2, D3).
#
#  1. the root build is not changed: `git diff <BASE> HEAD` is empty for src, libs, build.gradle.kts,
#     settings.gradle.kts, gradle, gradle.properties, detekt, .gitmodules, benchmark (BASE = bccd517,
#     the main of the E6 start), and ucfs-main/ has no Kotlin sources of its own (it compiles ../src/main);
#  2. org.ucfs:solver of UCFS-AI-dev at UCFS_COMMIT: from $UCFS_M2 if it holds a solver jar whose
#     manifest says UCFS-Commit = UCFS_COMMIT, UCFS-Dirty = false; otherwise built here from a clone
#     (publishSolverPublicationToMavenLocal into out/ucfs-m2, the recipe of Qilin's scripts/ucfs/bootstrap.sh);
#  3. the root build on libs/solver-new.jar (UCFS PR #50): `gradlew test jar` green, its test results
#     are the baseline (the taint graphs of the submodule benchmark/external-repos/cfl-idr are needed);
#  4. `gradlew -p ucfs-main -PucfsRepo=<2> clean test publishLibPublicationToMavenLocal
#     -Dmaven.repo.local=out/m2` exits 0; ucfs-main has >= 181 tests, 0 failed/errors/skipped;
#     every test case of the baseline except the class TestExtractEdgesFromSppfResult (file
#     src/test/kotlin/utils/TestExtractEdgesFromSppfResult.kt, no package; its SPPF fixtures use the node
#     classes of PR #50) is in ucfs-main with the same status (PASSED);
#  5. the published jar org.cfl_idr_with_gll:cfl-idr-with-gll:0.1.0-ai-SNAPSHOT: its top-level classes
#     (class files without '$') are exactly those of the root jar (same compiled sources; Kotlin 2.4 and
#     1.9.20 differ only in synthetic lambda classes '...$1'), its manifest says CflIdr-Commit = HEAD,
#     CflIdr-Dirty = false, UCFS-Commit = UCFS_COMMIT; its POM depends on org.ucfs:solver:0.1.0-ai-SNAPSHOT
#     and has no logback dependency;
#  6. the jar is compiled against UCFS-AI-dev, not PR #50: in `javap -c` of
#     org.cfl_idr_with_gll.ApproxUtilsKt the SPPF children are read with
#     RangeSppfNode.getChildren:()Ljava/util/ArrayList; (UCFS-AI-dev), not ...()Ljava/lang/Iterable; (PR #50).
# Usage: bash acceptance/E6/S1_ucfs_main.sh      (exit 0 = PASS, 1 = FAIL, 2 = environment)
#   JAVA_HOME = JDK 21 (default ~/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2); UCFS_M2 optional.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 2
BASE=bccd51773d6661f3ffb24ff77544a540a2f6afac
UCFS_COMMIT=bd1c1110674ce8c22c4281d766318563c8322341
UCFS_URL=https://github.com/UsatovPavel/UCFS-AI-dev.git
UCFS_VERSION=0.1.0-ai-SNAPSHOT
export JAVA_HOME="${JAVA_HOME:-$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}"
OUT="$ROOT/acceptance/E6/out"
LOGS="$OUT/logs"
mkdir -p "$LOGS"
FAILS=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILS=$((FAILS + 1)); }
env_die() { echo "ENV: $*"; echo "RESULT: ENV (S1_ucfs_main)"; exit 2; }
manifest_attr() { unzip -p "$1" META-INF/MANIFEST.MF | tr -d '\r' | sed -n "s/^$2: //p"; }
finish() {
    if [ "$FAILS" -eq 0 ]; then echo "RESULT: PASS (S1_ucfs_main)"; exit 0; fi
    echo "RESULT: FAIL (S1_ucfs_main, $FAILS failed)"; exit 1
}
[ -x "$JAVA_HOME/bin/java" ] || env_die "JAVA_HOME=$JAVA_HOME has no bin/java"
command -v unzip >/dev/null && command -v python3 >/dev/null || env_die "unzip and python3 are required"

# --- 1. root build unchanged ---------------------------------------------------------------------
git cat-file -e "$BASE^{commit}" 2>/dev/null || env_die "base commit $BASE is not in this repository"
if git diff --quiet "$BASE" HEAD -- src libs build.gradle.kts settings.gradle.kts gradle gradle.properties detekt .gitmodules benchmark; then
    pass "root build, sources, tests and libs/ unchanged since $BASE"
else
    fail "changed since $BASE: $(git diff --name-only "$BASE" HEAD -- src libs build.gradle.kts settings.gradle.kts gradle gradle.properties detekt .gitmodules benchmark | head -n 5 | tr '\n' ' ')"
fi
[ -f ucfs-main/build.gradle.kts ] && [ -f ucfs-main/settings.gradle.kts ] \
    && pass "ucfs-main/ is a standalone build" || fail "no ucfs-main/build.gradle.kts and settings.gradle.kts"
own_src="$(git ls-files ucfs-main | grep -E '\.(kt|java)$' || true)"
[ -z "$own_src" ] && pass "ucfs-main has no sources of its own" || fail "ucfs-main has its own sources: $own_src"
[ "$FAILS" -eq 0 ] || finish

# --- 2. org.ucfs:solver at UCFS_COMMIT -------------------------------------------------------------
solver_ok() {
    local j="$1/org/ucfs/solver/$UCFS_VERSION/solver-$UCFS_VERSION.jar"
    [ -f "$j" ] && [ "$(manifest_attr "$j" UCFS-Commit)" = "$UCFS_COMMIT" ] && [ "$(manifest_attr "$j" UCFS-Dirty)" = false ]
}
if [ -n "${UCFS_M2:-}" ] && solver_ok "$UCFS_M2"; then
    M2U="$UCFS_M2"
    pass "org.ucfs:solver from UCFS_M2=$UCFS_M2 (UCFS-Commit $UCFS_COMMIT)"
else
    M2U="$OUT/ucfs-m2"
    if ! solver_ok "$M2U"; then
        rm -rf "$OUT/ucfs-src" "$M2U"
        git clone -q --no-checkout "$UCFS_URL" "$OUT/ucfs-src" > "$LOGS/ucfs.log" 2>&1 || env_die "clone $UCFS_URL"
        git -C "$OUT/ucfs-src" -c advice.detachedHead=false checkout -q --detach "$UCFS_COMMIT" >> "$LOGS/ucfs.log" 2>&1 \
            || env_die "checkout $UCFS_COMMIT"
        (cd "$OUT/ucfs-src" && bash ./gradlew --console=plain -q publishSolverPublicationToMavenLocal "-Dmaven.repo.local=$M2U") \
            >> "$LOGS/ucfs.log" 2>&1 || env_die "UCFS build failed (log: $LOGS/ucfs.log)"
    fi
    solver_ok "$M2U" && pass "org.ucfs:solver built from UCFS-AI-dev @ $UCFS_COMMIT" || env_die "no solver jar @ $UCFS_COMMIT in $M2U"
fi

# --- 3. baseline: the root build on libs/solver-new.jar --------------------------------------------
if [ ! -f benchmark/external-repos/cfl-idr/src/main/taint/zertsecurity.dot ]; then
    git submodule update --init benchmark/external-repos/cfl-idr > "$LOGS/submodule.log" 2>&1 || env_die "submodule (network?)"
fi
rm -rf build/test-results/test
bash ./gradlew --console=plain test jar > "$LOGS/root.log" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "root build: gradlew test jar (libs/solver-new.jar)" || fail "root build exit $rc (log: $LOGS/root.log)"

# --- 4. ucfs-main: tests and publication ----------------------------------------------------------
M2="$OUT/m2"
rm -rf "$M2" ucfs-main/build/test-results
bash ./gradlew --console=plain -p ucfs-main "-PucfsRepo=$M2U" clean test publishLibPublicationToMavenLocal "-Dmaven.repo.local=$M2" \
    > "$LOGS/ucfs-main.log" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "ucfs-main: clean test publishLibPublicationToMavenLocal" || fail "ucfs-main build exit $rc (log: $LOGS/ucfs-main.log)"

python3 - build/test-results/test ucfs-main/build/test-results/test <<'PY'
import glob, os, sys
import xml.etree.ElementTree as ET
def cases(d):
    out = {}
    for p in glob.glob(os.path.join(d, "TEST-*.xml")):
        for tc in ET.parse(p).getroot().iter("testcase"):
            st = "PASSED"
            for k in ("failure", "error", "skipped"):
                if tc.find(k) is not None:
                    st = k.upper()
            out[(tc.get("classname"), tc.get("name"))] = st
    return out
base, var = cases(sys.argv[1]), cases(sys.argv[2])
excluded = "TestExtractEdgesFromSppfResult"  # no package (src/test/kotlin/utils/TestExtractEdgesFromSppfResult.kt)
want = {k: v for k, v in base.items() if k[0].split(".")[-1] != excluded}
bad_var = [k for k, v in var.items() if v != "PASSED"]
missing = [k for k in want if k not in var]
differ = [k for k in want if k in var and var[k] != want[k]]
extra = [k for k in var if k not in want]
print("  baseline: %d cases (%d not PASSED), excluded class: %d cases; ucfs-main: %d cases"
      % (len(base), sum(v != "PASSED" for v in base.values()), len(base) - len(want), len(var)))
ok = True
def check(cond, msg):
    global ok
    print(("PASS: " if cond else "FAIL: ") + msg)
    ok &= cond
check(len(var) >= 181, "ucfs-main has >= 181 test cases (%d)" % len(var))
check(not bad_var, "every ucfs-main case PASSED %s" % bad_var[:3])
check(all(v == "PASSED" for v in want.values()) and len(want) > 0, "baseline cases PASSED")
check(not missing, "every baseline case (except %s) runs in ucfs-main %s" % (excluded, missing[:3]))
check(not differ, "same status as the baseline %s" % differ[:3])
check(not extra, "no case in ucfs-main that the baseline lacks %s" % extra[:3])
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] || FAILS=$((FAILS + 1))

# --- 5. published artifact ----------------------------------------------------------------------
PUB="$M2/org/cfl_idr_with_gll/cfl-idr-with-gll/0.1.0-ai-SNAPSHOT"
JAR="$PUB/cfl-idr-with-gll-0.1.0-ai-SNAPSHOT.jar"
POM="$PUB/cfl-idr-with-gll-0.1.0-ai-SNAPSHOT.pom"
ROOTJAR="$(ls build/libs/cfl-idr-with-gll*.jar 2>/dev/null | grep -v -- '-all' | head -n 1)"
if [ -f "$JAR" ] && [ -f "$POM" ]; then
    pass "published $JAR"
    [ "$(manifest_attr "$JAR" CflIdr-Commit)" = "$(git rev-parse HEAD)" ] && pass "CflIdr-Commit = HEAD" \
        || fail "CflIdr-Commit '$(manifest_attr "$JAR" CflIdr-Commit)' != HEAD $(git rev-parse HEAD)"
    [ "$(manifest_attr "$JAR" CflIdr-Dirty)" = false ] && pass "CflIdr-Dirty = false" \
        || fail "CflIdr-Dirty '$(manifest_attr "$JAR" CflIdr-Dirty)' (commit everything first)"
    [ "$(manifest_attr "$JAR" UCFS-Commit)" = "$UCFS_COMMIT" ] && pass "UCFS-Commit = $UCFS_COMMIT" \
        || fail "UCFS-Commit '$(manifest_attr "$JAR" UCFS-Commit)' != $UCFS_COMMIT"
    python3 - "$POM" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {"m": "http://maven.apache.org/POM/4.0.0"}
deps = [(d.findtext("m:groupId", "", ns), d.findtext("m:artifactId", "", ns), d.findtext("m:version", "", ns))
        for d in ET.parse(sys.argv[1]).getroot().iter("{http://maven.apache.org/POM/4.0.0}dependency")]
ok = ("org.ucfs", "solver", "0.1.0-ai-SNAPSHOT") in deps and not any(g == "ch.qos.logback" for g, a, v in deps)
print(("PASS: " if ok else "FAIL: ") + "POM depends on org.ucfs:solver:0.1.0-ai-SNAPSHOT, no logback: %s" % deps)
sys.exit(0 if ok else 1)
PY
    [ $? -eq 0 ] || FAILS=$((FAILS + 1))
    if [ -n "$ROOTJAR" ]; then
        a="$(unzip -Z1 "$JAR" | grep '\.class$' | grep -v '\$' | sort)"
        b="$(unzip -Z1 "$ROOTJAR" | grep '\.class$' | grep -v '\$' | sort)"
        [ -n "$a" ] && [ "$a" = "$b" ] && pass "top-level classes of the published jar = those of the root jar ($(echo "$a" | wc -l))" \
            || fail "class lists differ: $(diff <(echo "$a") <(echo "$b") | head -n 4 | tr '\n' ' ')"
    else
        fail "no root jar in build/libs"
    fi
    # --- 6. compiled against UCFS-AI-dev ----------------------------------------------------------
    dump="$("$JAVA_HOME/bin/javap" -c -p -classpath "$JAR" org.cfl_idr_with_gll.ApproxUtilsKt 2>&1)"
    if echo "$dump" | grep -q 'org/ucfs/sppf/node/RangeSppfNode.getChildren:()Ljava/util/ArrayList;' \
        && ! echo "$dump" | grep -q 'RangeSppfNode.getChildren:()Ljava/lang/Iterable;'; then
        pass "ApproxUtilsKt reads RangeSppfNode.getChildren():ArrayList (UCFS-AI-dev API)"
    else
        fail "ApproxUtilsKt is not compiled against UCFS-AI-dev: $(echo "$dump" | grep -o 'RangeSppfNode.getChildren:[^ ]*' | sort -u | tr '\n' ' ')"
    fi
else
    fail "no published jar/pom in $PUB"
fi
finish
