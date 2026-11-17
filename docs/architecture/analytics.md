# Analytics

Google Analytics and Crashlytics, both from the Firebase project
`termphin-hexeosoft`: what is sent, when, and the consent rules behind it. The
privacy policy describes this by category and links to `analytics_service.dart`
as the complete list of events and fields.

`AnalyticsService` is the only thing that talks to them, through
`AnalyticsBackend` (`FirebaseAnalyticsBackend` in the app, a recorder in
tests - `test/support/analytics_recorder.dart`, installed for every test by
`flutter_test_config.dart`). The Firebase config comes in at build time from
outside the repository (`docs/release.md`); a build without it - a fork, a
desktop - has no backend and sends nothing.

- **Firebase does not start with the app.** Starting it writes installation
  ids to the device, so the Android manifest removes `FirebaseInitProvider`
  (iOS has no config file to auto-start from) and `FirebaseService.start()`
  brings it up from Dart only when there is a reason: consent on record, an
  account, push. Whoever starts it, `AnalyticsService` puts its own consent
  back in force through `FirebaseService.onStart`, so starting Firebase for an
  account never turns crash reports back on.
- **Collection is off until consent**, in the manifest and `Info.plist` as well
  as at runtime: analytics, Crashlytics and FCM auto-init all default to off,
  as do the advertising id and automatic screen reporting. Consent mode grants
  analytics storage only; nothing is ever granted for ads. `setConsent(false)`
  also deletes the crash reports kept on the device.
- Google Analytics adds `first_open`, `session_start` and `user_engagement`
  on its own once collection is on - the policy lists them. Parameters take no
  booleans, so a flag goes out as `true` or `false` spelled out.

Independently of Firebase, `ErrorReports` (`lib/services/app/error_reports.dart`)
hooks the same two error handlers from `main`; `AnalyticsService.installErrorHandlers`
chains after it, so both see every error. It keeps the last reports in shared
preferences, so a crash is still there after the restart, works with analytics
off, and sends nothing by itself: Settings → Feedback → Error reports lets the
user mail or share them. A `SocketException` - a transport closing, which
names the machine - is never sent to Crashlytics.

- **Events and property names are closed enums** (`AnalyticsEvent`,
  `AnalyticsProperty`): what is sent has to be readable off one list, both to
  keep the privacy policy honest and to stop a hostname reaching `capture()`
  under an ad-hoc key. A debug-only shape check rejects any string value
  carrying `@`, a slash or a newline - a tripwire, not a proof. **The policy
  links to this file as the complete list** (§8), so a new name needs no
  policy edit; a new kind of data, or a new provider, does.
- **Screen views are sent by hand.** The four main destinations are tabs in one
  `Stack` inside `MainShell`, not routes, so a `NavigatorObserver` would miss
  them and an `initState` hook would report all four on the first frame.
  `_MainShellState` reports on tab change; pushed screens report from
  `initState`.
- **`setting_changed` is emitted from `Setting.set`**, so no settings screen has
  to remember to. The value goes out only when it reduces to a scalar: a list
  reports its length, never its entries. `Setting.track: false` is for the ones
  written by a gesture rather than chosen.
- **Connection failures are classified where they are thrown.**
  `SshConnectException` carries a `SshFailureReason` alongside the message,
  because the message interpolates whatever it has to hand - addresses, a
  bastion's name, dartssh2's own text - and none of that can be reported. Its
  `toString()` is the bare message, so callers rendering `error.toString()`
  render what they did before. Pattern-matching English prose out of an error is
  what this exists to avoid.
- **The consent question is asked once in the app's life**, not in
  onboarding: `AnalyticsService.maybeAsk` puts a card over the home screen
  (`AnalyticsAskCard`) once there have been three successful connections and
  two days since the first, from the startup prompts in `app.dart` - only
  when nothing else interrupted that launch, and before the store prompt.
  "Sure" and "No thanks" are the same size and nothing is preselected,
  because a pre-ticked box is not consent (CJEU, Planet49). It is marked
  asked the moment it shows; leaving the home screen takes it down, and an
  unanswered question is a no. The Settings toggle calls the same
  `setConsent()`.
- **A yes recorded by the old onboarding is dropped once** (its box came
  ticked), so those users are asked like everyone else; a no stays a no.
- **Declining never starts Firebase.** With nothing else running it there is
  nothing to switch off; if an account or push starts it later, the
  `onStart` hook puts the no in force.
- **Retention is a project setting.** Google Analytics keeps event-level data
  for 2 or 14 months (Admin → Data retention); the policy's §6 has to match
  it. Crashlytics keeps crash reports for 90 days.
