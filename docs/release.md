# Building and releasing

Release builds, what a release ships, signing, export compliance and the
Android toolchain.

## Release builds

Use `scripts/build_release.sh` (`android` default, or `ios`). Android builds
both the AAB for Google Play and a universal APK. The iOS target refuses to run
off macOS and reads `APP_STORE_ID` from the environment; it only warns when it
is missing, and `ReviewPromptService.canOpenStoreListing` then hides the "Rate
Termphin" row. Both targets read `POSTHOG_API_KEY` the same way and warn
without it: such a build has analytics off.

**Builds are not obfuscated.** The source is public, so obfuscation would hide
nothing, and an unobfuscated build keeps readable Dart stack traces: a crash
from `captureFlutterErrors` names its functions and lines in PostHog as it
is, with no symbol files to keep or `flutter symbolize` to run.

## What a release ships

A GitHub release carries `termphin-<version>.apk` and `termphin-<version>.aab`,
each with a `.sha256` file and a build provenance attestation
(`gh attestation verify <file> -R Termphin/Termphin` proves it was built by
this repository's workflow from the tagged commit). The iOS build goes to
TestFlight only - an App Store-signed IPA installs nowhere else, so it is not
attached.

The APK is signed with the upload key, while Google Play re-signs what it
distributes with the app signing key it holds. The two installs therefore do
not update each other: someone moving between the GitHub APK and the Play
build has to uninstall first.

## Release workflow

`.github/workflows/release.yml` fires on a `vX.Y.Z` tag. It first checks the
tag - a dotted version matching `pubspec.yaml`, on a commit that is on
`main` - and runs `flutter analyze` and the tests. Then it creates a **draft**
release with notes rendered from that version's entry in
`assets/release_notes.yaml` (plus how to verify the APK), the Android and iOS
builds run in parallel, and only when every build succeeded is the draft
published. A failed build leaves a draft to delete, never a public release
without its files. It fails rather than guessing when the entry is
missing or the tag is not a dotted number, so give the `Unreleased` entry its
real number before tagging. Release tags are protected: once pushed, a `v*`
tag cannot be moved or deleted, so a broken release is fixed with the next
version (or the next `+N`), not by re-tagging.

A tag ending in `-ios.N` or `-android.N` (`v1.12.0-ios.22`) is a test build
for that platform alone: only that build runs, and its release is a
prerelease, so it never becomes the latest. `N` is the build number after the
`+` in `pubspec.yaml`, and the builds fail when it is not - TestFlight refuses
a build number it has already seen, so each test, and the final `vX.Y.Z`
after it, needs the `+N` bumped first, and the tag says which one it built.
It still needs the version's entry in `release_notes.yaml`. In the app a test
build is indistinguishable from the release apart from that number: Settings
shows `1.12.0 (22)`.

## Export compliance

`ITSAppUsesNonExemptEncryption` is **absent** from `ios/Runner/Info.plist`, and
that is a third state, not a quiet "false". The app ships its own ciphers
(pure-Dart AES-256-GCM and ChaCha20-Poly1305 in `secret_cipher.dart`/`aead.dart`,
plus PBKDF2 for backups) rather than relying solely on the platform's, so it
falls outside the "only standard encryption provided by the operating system"
exemption and false would be untrue.

`true` was tried and is wrong on its own: it asserts that approved export
documentation exists and that its `ITSEncryptionExportComplianceCode` sits
beside it. Uploads were refused at validation - "Invalid Export Compliance Code
... key value []" - instead of reaching the questions the key was assumed to
defer to. With the key absent, App Store Connect marks the build "Missing
Compliance" and asks per submission. Both keys come back together once the
documentation is filed and Apple issues a code - never `false`.

## Signing

A local release build reads `android/key.properties` (git-ignored: `storeFile`,
`storePassword`, `keyAlias`, `keyPassword`); without it the release build falls
back to the debug key. CI writes that file from its secrets. Play App Signing
holds the real app signing key, so the upload key is resettable from the Play
Console if it is ever lost. The committed `android/app/debug-keystore.jks` is
the public AOSP debug key and is meant to be there - it keeps the debug
signature stable across machines.

## Android toolchain

Gradle 9.6.1, AGP 9.4.0, Kotlin 2.3.21, `compileSdk` 37. Two things about AGP 9
before touching `android/`:

- **`resValues` is opt-in now.** The build types override `app_name` with one,
  which is what labels a debug install as such, so `buildFeatures { resValues =
  true }` in `android/app/build.gradle.kts` is load-bearing - without it the
  configuration phase fails outright.
- **Built-in Kotlin is not on yet.** `android.builtInKotlin=false` in
  `gradle.properties`, and the app still applies `kotlin-android`. Migrating is
  blocked from outside: `in_app_review` and `posthog_flutter` apply KGP
  themselves. That is on those plugins to fix first.

Gradle's own output is gitignored (`/android/build/`,
`/android/ringbuffer-tests/build/`, `**/.gradle/`) - the root `/build/` rule
never covered them.
