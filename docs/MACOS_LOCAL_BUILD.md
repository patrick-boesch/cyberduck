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
4. The completed application is `osx/target/Cyberduck.app` inside the checkout. **⌘R** runs the Maven build and then
   launches the **Cyberduck Local** target's `Cyberduck.app` product without attaching LLDB.

The scheme's Build and Run actions select the same **Cyberduck Local** application target. Its only build phase runs
the full Maven pipeline, which invokes the original native `app` target internally. The local target neither generates
an Info.plist nor signs the result. Its output directory is `$(PROJECT_DIR)/osx/target`, matching Maven's bundle
location independently of Xcode's DerivedData directory. Xcode resolves `Contents/MacOS/Cyberduck` through this
product and its `CFBundleExecutable` metadata.

The previous launch configuration used a `PathRunnable` string with `$(PROJECT_DIR)` and an aggregate target for macro
expansion. Xcode reported `IDELaunchErrorDomain Code 9 / Executable Not Found / (null)` with that setup.
The scheme uses `BuildableProductRunnable` referencing the local application target directly.

Referencing the original native `app` target as the runnable causes Xcode to build it again after Maven, even with
implicit dependencies disabled and its Build action checkboxes cleared. That second build lacks Maven's JVM and
version settings and overwrites the packaged Info.plist: `VMOptions` becomes the literal `$JVM_RUNTIME_ARGS`, causing
Java to exit with `ClassNotFoundException: $JVM_RUNTIME_ARGS`. Keeping Build and Run on the local application target
prevents that second build.

After pulling an update to the shared scheme, use **Product → Scheme → Edit Scheme → Run → Info** to confirm that
Executable is **Cyberduck.app**. If Xcode still shows a locally overridden executable, select the native
**Cyberduck.app** product belonging to **Cyberduck Local** there. Do not select the original native `app` target for
Build or Run: Maven already builds and packages it.

After a successful build, the bundle can also be opened directly with
`open osx/target/Cyberduck.app` from the checkout root.

The script discovers Maven in the existing PATH and common Homebrew locations. A valid JDK 21 in JAVA_HOME is used;
an inherited Java 11 or incomplete JDK does not prevent discovery of another JDK. The script next checks
`/usr/libexec/java_home -F -v 21`, `brew --prefix openjdk@21`, and standard Apple Silicon/Intel Homebrew locations.
Every candidate must report Java 21 and contain `javac`, `include/jni.h` and `include/darwin/jni_md.h`.
The selected JDK is printed and exported to Maven, which passes it to the native Xcode builds.

Set `CYBERDUCK_JAVA_HOME` to explicitly select an unregistered JDK. This override is strict: an invalid override
stops the build with its path in the error message. No global Java configuration is changed.

If no JDK 21 is installed, install one before building. With Homebrew:

```sh
brew install openjdk@21
bash scripts/build-macos.sh --check
```

The build can discover the Homebrew JDK directly; system-wide symlink registration is unnecessary.
See the [Homebrew formula](https://formulae.brew.sh/formula/openjdk@21) for installation details.
The script does not install tools or change the active Xcode installation.

The shared scheme uses an application target with a script build phase, replacing the legacy external target
that reported an internal Xcode consistency error when preflight failed. The script exits with the actual build error.
A successful build setup creates `.build/jdk` pointing to the selected JDK. Xcode's native header search paths include
that location so its indexer can resolve JNI headers even when Xcode itself has no matching JAVA_HOME.

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
| Selected JDK link for Xcode header lookup | `.build/jdk` |
| Xcode scheme products/intermediates | `.build/xcode/Products/`, `.build/xcode/Intermediates/` |
| Xcode DerivedData | `.build/xcode/DerivedData/` |
| Native Maven-invoked Xcode intermediates/caches | `core/dylib/target/xcode/`, `osx/target/xcode/` |

The outer Xcode scheme and nested native builds use separate intermediate directories to avoid recursive build
database locks. Shared workspace settings keep Xcode's output in the checkout; existing per-user workspace settings
can override shared settings. If necessary, select the shared project-relative locations in File → Project Settings.
Installed tools and their own installation data remain outside the checkout.

Product → Clean Build Folder clears the outer Xcode build data. To clean the Maven reactor and packaged app,
run `bash scripts/build-macos.sh clean`. The reusable `.build/` caches and JDK link are retained.
Build output is ignored by Git.

## Verification

Initial checks: Bash syntax; OpenStep project parsing and existing-target preservation; XML/plist parsing;
and seven build-script cases using mocked macOS tools (preflight, paths with spaces, failure propagation, clean,
unsupported JDK/OS and invalid actions). These checks do not compile Java or native code.

Follow-up verification covers the reported missing-Ant failure: preflight and the build wrapper succeed with no
standalone Ant on PATH, and missing macOS JNI headers produce a specific error before Maven starts.

The JDK-selection regression checks cover an inherited Java 11 with an available Homebrew JDK 21, a valid inherited
JDK 21, missing JDKs, strict overrides, missing JNI headers, paths with spaces and Maven exit-status propagation.
The initial project checks covered the aggregate target, its script phase and the JNI header paths using mocked tools;
Xcode's indexer and native error presentation still require verification on macOS.

The initial launch-configuration checks covered the native product reference, app output directories and
`CFBundleExecutable`. Those structural checks did not catch Xcode's second native build.

The startup correction was verified on Apple Silicon with macOS 26.6.2 and Xcode 26.6: the local scheme build succeeds
and its outer dependency graph contains only `Cyberduck Local`. The final bundle retains Maven's VM options and
version metadata. A direct release launch remains running after 20 seconds; a native sample confirms ARM64 execution,
the embedded JVM and the `NSApplication` event loop. The diagnostic process was then deliberately terminated.
Existing scheme customizations and the original native targets were checked for preservation. No full test suite ran.

`codesign --verify` still reports missing or invalid signatures with `-DskipSign`; signing was not changed because
the observed direct start succeeds with those signatures. The local build also logs a Sparkle updater EdDSA-key error
without terminating the application. Visible UI, double-click and Xcode's Run action remain manual checks.
Startup and build diagnostics are saved under `osx/target/startup-diagnosis/` in the diagnosing checkout.

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
