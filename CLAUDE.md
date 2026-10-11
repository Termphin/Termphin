# CLAUDE.md

Guidance for AI coding agents (and people) working on Termphin's code. It
holds only what every task needs: commands, where things live, and the rules
that must not be broken. The reasoning behind each subsystem is in
`docs/architecture/`, read on demand - the index is below.

## Commands

```bash
flutter pub get                    # Install dependencies
flutter analyze                    # Lint
flutter test                       # Run tests
flutter test test/foo_test.dart    # Run a single test
flutter test --tags security       # Security rules suite (test/security/), also part of the full run
flutter test --exclude-tags live   # Everything except the suites that need a real sshd
flutter build apk                  # Debug-signed Android build
scripts/build_release.sh [android|ios]  # Release build: AAB + APK, or IPA

dart run slang                     # Regenerate i18n (lib/i18n/strings.g.dart) after editing the JSON

python3 scripts/generate_icons.py && dart run flutter_launcher_icons  # Regenerate launcher icons
python3 scripts/generate_quick_action_icons.py                        # Regenerate quick action icons

scripts/measure_memory.sh --watch 5       # Real process memory, needs a device
scripts/scan_vulnerabilities.sh           # Known CVEs in dependencies (osv-scanner)
scripts/update_agent_from_github.sh [tag] # Pull the termphin-agent binaries of a release
```

`test/live/` runs against a real `sshd` and skips itself unless
`TERMPHIN_LIVE_SSH_PORT` is set (see `test/live/README.md`).

## Repository map

Termphin is a Flutter SSH client (package `termphin`).

| Path | What it is |
|---|---|
| `lib/`, `test/` | The app and its tests. `lib/` is layered and split by topic inside the big layers; `test/` mirrors it folder for folder. Layout in `docs/architecture/overview.md`. |
| `assets/` | Flutter assets: fonts (with their licences), icons, the gzipped agent binaries, `release_notes.yaml`, `whats_new.yaml`. |
| `android/`, `ios/` | Platform projects. Native channels live in `android/app/src/main/kotlin` and `ios/Runner`. |
| `macos/`, `windows/`, `linux/` | Desktop platform projects, work in progress. |
| `scripts/` | What builds or maintains the app: `build_release.sh`, icon generators, `update_agent_from_github.sh`, `measure_memory.sh`. |
| `integration_test/` | Outside `test/` on purpose. |
| `third_party/phosphor_flutter/` | The icon package, vendored for its fonts. |
| `docs/` | Developer documentation and the source of the legal pages (`docs/legal/`). |
| `branding/` | The logo and the store graphics built from it, covered by `TRADEMARKS.md`. |
| `repos/` | Sibling repositories as git submodules (`terminal_view`, `termphin-agent`, `tray_kit`), for working on them alongside the app. The app builds without them. |

## Documentation index

| Read this | When you touch |
|---|---|
| `docs/architecture/overview.md` | Startup, state, the `lib/` layout |
| `docs/architecture/ssh.md` | `SshService`, host keys, jump hosts, reconnecting, keepalive, connectivity |
| `docs/architecture/predictive-echo.md` | Local echo (run its fuzz test) |
| `docs/architecture/platform.md` | Foreground service, iOS suspension, local network permission, quick actions, sharing to Termphin |
| `docs/architecture/data.md` | Storage, groups, `Setting<T>`, backup and restore |
| `docs/architecture/transfers.md` | SFTP transfers, copy and move, download location |
| `docs/architecture/ui.md` | Screens, terminal widgets, toolbar, dock, notifications, sheets, layout, theme |
| `docs/architecture/desktop.md` | Anything that differs off a phone: hiding by platform, dialogs vs sheets, the title bar, shortcuts, Esc, right click |
| `docs/architecture/analytics.md` | Anything that reaches PostHog |
| `docs/architecture/onboarding.md` | First run, review prompt, changelog and what's new |
| `docs/release.md` | Building, what a release ships, signing, export compliance, the Android toolchain |

## Rules that always apply

### Style

- **No `//` comments in code - docstrings (`///`) only.** Put the *why* of a
  member into its docstring; analyzer directives (`// ignore:`) are the only
  exception.
- English everywhere: identifiers, docstrings, strings.
- Commit messages are one Conventional Commits title line
  (`type(scope): subject`), no body.
- `main` is protected: every change lands through a pull request, squashed,
  with CI green - so the PR title is the commit message. Release tags `v*`
  cannot be moved or deleted.
- A bug fix comes with a test that fails without it.

### Copy in the app

Termphin builds for several platforms and is meant to run everywhere in time,
so the product is described as an SSH client, never by its platform.

- **Never write "SSH client for Android", "Android app" or "free on Android"**
  in anything a user reads. The platform belongs on the download page and in
  a store listing's own fields.
- **A phone is still fine as the example.** "Your session survives when you
  lock your phone" describes the situation, not the product.
- **Platform-specific behaviour is described by what it does**: "lets the
  system keep Termphin running", not "lets Android keep it running". Code
  docstrings may name the platform.

`lib/utils/platform_info.dart` exports `isAndroidPlatform`/`isIOSPlatform`/
`isDesktopPlatform` (off `defaultTargetPlatform`, so tests can override them).
Branch on those, not on comparisons spelled out at each call site.

### i18n

`slang`. Source: `lib/i18n/strings_en.i18n.json`. Generated:
`lib/i18n/strings.g.dart`.

**Every user-facing string** (labels, hints, tooltips, toasts, dialog
titles/content, button text, connection log lines) goes into
`strings_en.i18n.json` and is referenced via `Translations.of(context)` /
`t.section.key`. Never hardcode a string the user can see. Run `dart run slang`
after editing the JSON.

### Code

- **State lives in Riverpod providers**; a provider that fronts a `Setting`
  only republishes it. **Settings are `Setting<T>`**, and one not listed in
  `loadAppSettings()` reads as its default forever. Tests must put the
  process-wide values back with `await terminalSettings.load()` in `setUp`
  (`docs/architecture/data.md`).
- **UI reaches the session manager through `sshSessionManagerProvider`**, never
  `SshSessionManager.instance` (only `main.dart`, the composition root, does),
  so a test's override reaches every call.
- **A new setting goes into the backup**: export and import in
  `lib/services/backup/app_preferences_backup.dart` (`terminalSettings` or
  `appPreferences`), plus an alternative value in
  `test/services/settings/app_settings_test.dart`, whose round-trip test
  fails otherwise. Only device state (a drag position, the backup's own
  timestamp) goes to `_notBackedUp` there instead. The same holds for a new
  field on a record or group: it has to survive export and import, order
  included.
- **Colours come from the context**: `context.colors.textPrimary`, never a
  constant, so the widget repaints with the palette. That makes the expression
  non-`const`; drop the `const`. Fade to `someColor.invisible`, never
  `Colors.transparent`. Both palettes are pinned by
  `test/theme/palette_contrast_test.dart`.
- **Use the shared kit in `lib/widgets/ui/`** instead of hand-rolling:
  `showConfirmDialog` (`destructive: true` for anything that loses data),
  `showTextInputDialog`, `SettingsTile`/`SettingsSwitchTile`,
  `copyToClipboard`, `openExternalUrl`.
- **Transient feedback is `AppNotifications`, sheets are `showAppSheet`.** Do not
  use `ScaffoldMessenger`/`SnackBar` or `showModalBottomSheet`.
- **Pages, forms and windows open through `pushAppPage`, `pushAppForm` and
  `pushAppWindow`**, never a `MaterialPageRoute` of your own: each picks the
  desktop's presentation (a page beside the sidebar with no back arrow, a
  dialog, a large dialog). `showAppSheet` is a dialog on a desktop.
- **Screens hide things by what the system can do, not by its name.** They
  ask `platformHas(PlatformFeature.x)` or `isDesktopPlatform`; a new thing to
  hide is a new `PlatformFeature`. The named getters stay for wording that
  really is one platform's (the App Store vs Play). `defaultTargetPlatform` and
  `Platform.isX` never appear in `lib/screens` or `lib/widgets` -
  `test/architecture/platform_branching_test.dart` enforces it
  (`docs/architecture/desktop.md`).
- **Anything that closes closes with Esc on a desktop**, and a desktop
  shortcut is an `AppCommand`, never a `Shortcuts` widget of its own.
- **A desktop action with a key shows the key** - in its tooltip
  (`AppCommands.tooltip`), its menu row (`ShortcutHint`) and the title bar's
  menus, which a screen fills through a `ContextMenuScope` rather than a
  fixed list (`docs/architecture/desktop.md`).
- **Radii are `AppTheme.radiusXs…`, never a number**: they are smaller on a
  desktop, and getters, so the expression is not `const`.
- **No sliders.** Numeric settings use `StepperRow`/`ValueStepperRow`.
- **Scrolling content takes its reading width from `ContentGutter`**, not
  `DesktopContentWidth`, which boxes the scroll view.
- **Anything that shows a machine name, host or username honours
  `anonymizeProvider`.**
- **Analytics names are closed enums** (`AnalyticsEvent`, `AnalyticsProperty`);
  a name added to either must also be added to the privacy policy's §4 tables
  (`docs/architecture/analytics.md`). The PostHog key comes in at build time
  (`--dart-define=POSTHOG_API_KEY`); a build without it sends nothing.
- **`ITSAppUsesNonExemptEncryption` stays absent** from `Info.plist`; neither
  `true` nor `false` is right (`docs/release.md`).

## Sibling repositories

- **`terminal_view`** - our fork of `xterm` 4.0.0, at
  https://github.com/Termphin/terminal_view, published to pub. The app depends
  on the pub release (the version is in `pubspec.yaml`), not a path. To work
  on both at once, add a temporary `dependency_overrides` pointing at a local
  clone. Selection behaviour lives in that repo's `lib/src/ui/render.dart`.
- **`tray_kit`** - the desktop tray icon plugin (Linux over D-Bus in Dart,
  Windows, macOS), at https://github.com/Termphin/tray_kit, published to pub.
  Same workflow as `terminal_view`: a temporary `dependency_overrides` to
  `repos/tray_kit` to work on both.
- **`termphin-agent`** - the Rust helper that keeps a remote shell alive across
  disconnects, uploaded over SSH by `RemoteAgentService`. Source at
  https://github.com/Termphin/termphin-agent; this repo ships only the prebuilt
  binaries and checksums in `assets/termphin-agent/`, **gzipped**: App Store
  validation refuses any Mach-O inside the app bundle, though nothing here runs
  on the device - it is bytes on their way to the user's own server. The
  digests in `manifest.properties` stay the helper's own, not the archive's, so
  `RemoteAgentService` checks what it uploads; `bundled_agent_assets_test.dart`
  pins that pairing. Run `scripts/update_agent_from_github.sh [tag]` after
  every agent release or the app ships stale binaries.
- **Issues** - bug reports and ideas go to https://github.com/Termphin/Termphin
  (`ProjectUrls.issues` is what Settings → Feedback links to); a vulnerability
  goes to `contact@termphin.dev`, never to a public issue.
