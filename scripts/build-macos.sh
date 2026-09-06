#!/bin/bash
#
# Copyright (c) 2026 Patrick Bösch.
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License, version 3.
# This program is distributed WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the LICENSE file for details.
#
# Build the complete macOS app using the existing Maven/Ant/Xcode pipeline.
set -euo pipefail

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

action="${1:-build}"
[[ $# -le 1 ]] || fail "Usage: $0 [build|clean|--check]"
case "$action" in
    build|clean|--check) ;;
    *) fail "Unsupported action '$action'. Use build, clean or --check." ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"
[[ -f pom.xml && -d Cyberduck.xcodeproj ]] || fail "Run this script from a Cyberduck checkout."
[[ "$(uname -s)" == Darwin ]] || fail "The macOS app requires macOS and an existing Xcode installation."

# Xcode launched from Finder does not inherit a login shell's Homebrew PATH.
export PATH="${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}:/opt/homebrew/bin:/usr/local/bin"
command -v mvn >/dev/null || fail "Apache Maven is missing. Install Maven and retry."
# Ant runs inside maven-antrun-plugin; no standalone ant executable is needed.
command -v xcrun >/dev/null || fail "Xcode command-line tools are missing."
xcrun --find xcodebuild >/dev/null || fail "Select the existing full Xcode installation in Xcode > Settings > Locations."
xcrun --sdk macosx --show-sdk-path >/dev/null || fail "The selected Xcode installation has no macOS SDK."

# An inherited JAVA_HOME (for example Java 11 from Xcode) is only a candidate.
# Keep an explicit project-specific override strict; otherwise find a complete JDK 21.
select_jdk21() {
    local candidate="${1:-}" properties major
    [[ -n "$candidate" && -x "$candidate/bin/java" && -x "$candidate/bin/javac" ]] || return 1
    [[ -r "$candidate/include/jni.h" && -r "$candidate/include/darwin/jni_md.h" ]] || return 1
    candidate="$(cd "$candidate" && pwd -P)" || return 1
    properties="$("$candidate/bin/java" -XshowSettings:properties -version 2>&1)" || return 1
    major="$(printf '%s\n' "$properties" | awk '/java.specification.version =/ {print $3; exit}')"
    [[ "$major" == 21 ]] || return 1
    JAVA_HOME="$candidate"
}

inherited_java_home="${JAVA_HOME:-}"
if [[ -n "${CYBERDUCK_JAVA_HOME:-}" ]]; then
    select_jdk21 "$CYBERDUCK_JAVA_HOME" ||
        fail "CYBERDUCK_JAVA_HOME must point to a complete macOS JDK 21 with JNI headers: $CYBERDUCK_JAVA_HOME"
elif select_jdk21 "$inherited_java_home"; then
    :
elif select_jdk21 "$(/usr/libexec/java_home -F -v 21 2>/dev/null || true)"; then
    :
else
    jdk_found=false
    if command -v brew >/dev/null; then
        jdk_prefix="$(brew --prefix openjdk@21 2>/dev/null || true)"
        if [[ -n "$jdk_prefix" ]] && select_jdk21 "$jdk_prefix/libexec/openjdk.jdk/Contents/Home"; then
            jdk_found=true
        fi
    fi
    if [[ "$jdk_found" == false ]]; then
        for candidate in \
            /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
            /usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home; do
            if select_jdk21 "$candidate"; then
                jdk_found=true
                break
            fi
        done
    fi
    [[ "$jdk_found" == true ]] ||
        fail "No complete macOS JDK 21 found. Inherited JAVA_HOME: ${inherited_java_home:-unset}. Install JDK 21 (for example: brew install openjdk@21), or set CYBERDUCK_JAVA_HOME to an existing macOS JDK 21 with JNI headers."
fi
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
printf 'Using JDK 21: %s\n' "$JAVA_HOME"

if [[ "$action" == --check ]]; then
    printf 'Prerequisites found. Repository: %s\n' "$repo_root"
    printf 'JDK: %s\nMaven: %s\n' "$JAVA_HOME" "$(command -v mvn)"
    exit 0
fi

# Keep caches outside target/: Maven clean removes the reactor's target folders.
mkdir -p "$repo_root/.build/maven-repository" "$repo_root/.build/tmp"
# Give Xcode's indexer a stable header path without modifying system Java settings.
jdk_link="$repo_root/.build/jdk"
[[ ! -e "$jdk_link" || -L "$jdk_link" ]] || fail "Expected a symlink at $jdk_link."
ln -sfn "$JAVA_HOME" "$jdk_link"
export TMPDIR="$repo_root/.build/tmp/"
maven_args=(
    --batch-mode --no-transfer-progress
    "-Dmaven.repo.local=$repo_root/.build/maven-repository"
    -Dstyle.color=never
    -pl osx -am
    -DskipTests -DskipSign -Drevision=0
    -Pno-testcontainers
)
if [[ "$action" == clean ]]; then
    exec mvn "${maven_args[@]}" clean
fi

mvn "${maven_args[@]}" verify
app="$repo_root/osx/target/Cyberduck.app"
[[ -x "$app/Contents/MacOS/Cyberduck" ]] || fail "Maven finished without the expected app executable: $app"
printf '\nBuilt: %s\n' "$app"
