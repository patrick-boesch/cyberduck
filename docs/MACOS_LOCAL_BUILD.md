# Local macOS builds

This fork removes the automatic donation reminder on macOS quit. The reminder controller, its scheduling and the
update-restart observer used only to suppress that reminder have been removed. Existing transfer/connection
confirmation and application cleanup remain in place. This removes the reported crash trigger; it does not establish
the underlying cause of the original crash without a macOS crash report or a reproduction.

## Prerequisites

- An existing full Xcode installation, selected under Xcode → Settings → Locations → Command Line Tools.
- A complete macOS JDK 21 (including JNI headers) and Apache Maven 3.5 or newer.
- Network access for Maven dependencies, including the upstream Cyberduck artifacts and bundled Java runtime.

Ant is supplied by the repository's `maven-antrun-plugin`; this build does not need a separate `ant` executable.

The repository builds Java code plus native Cocoa components. The native `app` target alone does not build and
package all Java dependencies. The **Cyberduck Local** scheme uses the existing Maven/Ant pipeline for the complete app.

## Build from Xcode

1. Use the existing checkout of this fork and select the branch containing this change. Preserve any local changes.
2. Open `Cyberduck.xcodeproj` in the existing Xcode installation.
3. Select **Cyberduck Local** and **My Mac**, then press **⌘B**.
4. The completed application is `osx/target/Cyberduck.app` inside the checkout. **⌘R** is configured to launch it
   without attaching LLDB to the Java application.

The script discovers Maven in the existing PATH and common Homebrew locations. It discovers JDK 21 through
`/usr/libexec/java_home` if JAVA_HOME is unset. Set JAVA_HOME explicitly for an unregistered JDK. It does not install
tools or change the active Xcode installation. Preflight also checks `include/jni.h` and
`include/darwin/jni_md.h` in the selected JDK before Maven starts.

The first build downloads many dependencies and a bundled runtime; later builds reuse the project-local Maven cache.
Builds skip tests, signing and installers. The scheme is for local development, not distribution or notarization.
For Java source debugging, use the existing upstream Maven debug workflow described in the main README.

## Terminal equivalent

Run from the checkout:

```sh
bash scripts/build-macos.sh --check
bash scripts/build-macos.sh
```

The script resolves the checkout from its own location, even if called from a different working directory.
Only the macOS Maven module and its reactor dependencies are selected (`-pl osx -am`); no CLI or Windows application
is requested. The script returns a failed Maven build's exit status and does not launch an existing stale app.

## Output paths

| Output | Location relative to the checkout |
| --- | --- |
| Complete application | `osx/target/Cyberduck.app` |
| Maven module outputs | Each module's `target/` |
| Maven dependency cache | `.build/maven-repository/` |
| Build temporary files | `.build/tmp/` |
| Xcode scheme products/intermediates | `.build/xcode/Products/`, `.build/xcode/Intermediates/` |
| Xcode DerivedData | `.build/xcode/DerivedData/` |
| Native Maven-invoked Xcode intermediates/caches | `core/dylib/target/xcode/`, `osx/target/xcode/` |

The outer Xcode scheme and nested native builds use separate intermediate directories to avoid recursive build
database locks. Shared workspace settings keep Xcode's output in the checkout; existing per-user workspace settings
can override shared settings. If necessary, select the shared project-relative locations in File → Project Settings.
Installed tools and their own installation data remain outside the checkout.

Product → Clean Build Folder, or `bash scripts/build-macos.sh clean`, runs Maven clean on the selected reactor.
The reusable `.build/` caches are retained. Build output is ignored by Git.

## Verification

Completed checks: Bash syntax; OpenStep project parsing and existing-target preservation; XML/plist parsing;
and seven build-script cases using mocked macOS tools (preflight, paths with spaces, failure propagation, clean,
unsupported JDK/OS and invalid actions). These checks do not compile Java or native code.

Follow-up verification covers the reported missing-Ant failure: preflight and the build wrapper succeed with no
standalone Ant on PATH, and missing macOS JNI headers produce a specific error before Maven starts.

The authoring environment is Linux without Xcode. A complete macOS build and the configured ⌘R launch have **not**
been verified there.

On the Mac, perform one build without signing and then these short manual checks:

1. Launch the newly built app and quit with ⌘Q, without a connection. No donation reminder should appear.
2. Repeat with an open connection. With connection confirmation enabled, check Cancel, Review and Quit Anyway.
3. With a running test transfer, check that Cancel keeps the app open and Quit still performs the existing shutdown.

Use a disposable remote folder for the transfer check. No full test suite, integration servers or simulators are
needed for this change. If the build fails, inspect the first actionable error and stop repeated attempts unless a
change addresses that error. If quitting still crashes, collect the macOS crash report and the exact quit path.

## Finder integration: separate future slice

Cyberduck's shared Java core also powers [Mountain Duck](https://docs.cyberduck.io/mountainduck/), which already
provides Finder access to remote storage.

A [Finder Sync extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html)
adds badges and menus; it does not supply a mounted filesystem or a synchronization engine.
For a new native integration, Apple's
[replicated File Provider](https://developer.apple.com/documentation/fileprovider/replicated-file-provider-extension)
is a candidate for Finder-visible files with on-demand downloads and background uploads.
This presents a system-managed local folder, as demonstrated by Mountain Duck's
[Integrated mode](https://docs.cyberduck.io/mountainduck/connect/integrated/), rather than a traditional remote volume.

Suggested slices, not implemented here:

1. Decide between an actual mounted volume and File Provider semantics; identify the required server protocol.
2. Prototype a read-only Finder integration for one connection, with a native extension and a background protocol service.
3. Add writes, upload retries, atomic replacement, rename/delete and conflict handling.
4. Add reconnect/offline behavior, credential sharing through Keychain, lifecycle management and packaging.

The main engineering risks are reliable writes during network loss, concurrent edits and the native-extension/Java-core
process boundary. The existing repository contains no ready-made File Provider or FUSE mounting component.
