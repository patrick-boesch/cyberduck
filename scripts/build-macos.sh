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
command -v ant >/dev/null || fail "Apache Ant is missing. Install Ant 1.10.1 or newer and retry."
command -v xcrun >/dev/null || fail "Xcode command-line tools are missing."
xcrun --find xcodebuild >/dev/null || fail "Select the existing full Xcode installation in Xcode > Settings > Locations."
xcrun --sdk macosx --show-sdk-path >/dev/null || fail "The selected Xcode installation has no macOS SDK."

if [[ -z "${JAVA_HOME:-}" ]]; then
    JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null)" || fail "Install JDK 21 or set JAVA_HOME to an existing JDK 21."
fi
[[ -x "$JAVA_HOME/bin/java" && -x "$JAVA_HOME/bin/javac" ]] || fail "JAVA_HOME must point to a full JDK 21."
java_version="$("$JAVA_HOME/bin/java" -XshowSettings:properties -version 2>&1)"
java_major="$(printf '%s\n' "$java_version" | awk '/java.specification.version =/ {print $3; exit}')"
[[ "$java_major" == 21 ]] || fail "JDK 21 is required; JAVA_HOME reports Java $java_major."
export JAVA_HOME

if [[ "$action" == --check ]]; then
    printf 'Prerequisites found. Repository: %s\n' "$repo_root"
    printf 'JDK: %s\nMaven: %s\nAnt: %s\n' "$JAVA_HOME" "$(command -v mvn)" "$(command -v ant)"
    exit 0
fi

# Keep caches outside target/: Maven clean removes the reactor's target folders.
mkdir -p "$repo_root/.build/maven-repository" "$repo_root/.build/tmp"
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
