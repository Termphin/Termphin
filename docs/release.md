# Building and releasing

Release builds, what a release ships, signing, export compliance and the
Android toolchain.

## Release builds

Use `scripts/build_release.sh` (`android` default, or `ios`). Android builds
both the AAB for Google Play and a universal APK. The iOS target refuses to run
off macOS and reads `APP_STORE_ID` from the environment; it only warns when it
is missing, and `ReviewPromptService.canOpenStoreListing` then hides the "Rate
Termphin" row. Both targets take the Firebase config from
`~/.config/termphin/firebase` (`TERMPHIN_FIREBASE_DIR` overrides it; in CI the
`FIREBASE_CONFIG_BASE64` secret, a base64 `tar.gz` of that directory) and warn
without it: such a build has no analytics, crash reports, accounts or push.
The directory holds `dart-defines.json` (passed as `--dart-define-from-file`),
`google-services.json` and `GoogleService-Info.plist`;
`scripts/firebase_config.sh` copies the last two into the tree, where they are
git-ignored, and writes `ios/Flutter/Firebase.xcconfig` with the reversed iOS
client id, the URL scheme Google sign-in returns through. **None of it is ever
committed.** `dart-defines.json` also carries RevenueCat's public SDK keys
(`REVENUECAT_ANDROID_KEY`, `REVENUECAT_IOS_KEY`); without them the build sells
nothing. RevenueCat's secret API key and the webhook's `Authorization` value
live beside it in `~/.config/termphin/` and never go into a build.

The iOS app signs with the `Termphin` App Store profile, which carries Push
Notifications and Sign in with Apple (`ios/Runner/Runner.entitlements`). A
capability added to the bundle id invalidates the profile: make a new one and
put it into the `IOS_PROVISIONING_PROFILE_BASE64` secret.

**Builds are not obfuscated.** The source is public, so obfuscation would hide
nothing, and an unobfuscated build keeps readable Dart stack traces: a crash
reported to Crashlytics names its functions and lines as it is, with no
symbol files to keep or `flutter symbolize` to run.

## What a release ships

A GitHub release carries the release notes and no files: each build goes
straight to its store's testing. The Android bundle is released on Play's
closed testing track (`alpha`) by `scripts/play_upload.py`, with the version's
entry in `assets/release_notes.yaml` as its notes (one line per item, cut at
Play's 500 characters); the iOS build goes to TestFlight. Promoting either to
production is done by hand in Play Console and App Store Connect.

`play_upload.py` signs in as the service account whose key is the
`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` secret (locally
`~/.config/termphin/google-service-account.json`). In Play Console give that
account "Release apps to testing tracks" and nothing that reaches production,
so a leaked key cannot ship to users. Run by hand it uploads a
locally built bundle the same way:
`python3 scripts/play_upload.py build/app/outputs/bundle/release/app-release.aab 1.15.0 alpha`
(needs `google-auth` and `pyyaml`).

## Release workflow

`.github/workflows/release.yml` fires on a `vX.Y.Z` tag. It first checks the
tag - a dotted version matching `pubspec.yaml`, on a commit that is on
`main` - and runs `flutter analyze` and the tests. Then it creates a **draft**
release with notes rendered from that version's entry in
`assets/release_notes.yaml`, the Android and iOS builds run in parallel, each
ending in its store's testing, and only when every build succeeded is the
draft published. A failed build leaves a draft to delete, never a public
release for a build that did not ship. It fails rather than guessing when the
entry is missing or the tag is not a dotted number, so give the `Unreleased`
entry its real number before tagging. Release tags are protected: once pushed, a `v*`
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
(pure-Dart AES-256-GCM in `secret_cipher.dart`/`aead.dart`, PBKDF2 for backups,
and the SSH transport ciphers in `dartssh2`) rather than relying solely on the
platform's, so it
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
  blocked from outside: `in_app_review` applies KGP
  themselves. That is on those plugins to fix first.

Gradle's own output is gitignored (`/android/build/`,
`/android/ringbuffer-tests/build/`, `**/.gradle/`) - the root `/build/` rule
never covered them.
