# Analytics

PostHog: what is sent, when, and the consent rules behind it. The privacy policy's tables are written from the enums described here.

PostHog via `posthog_flutter`, replacing Sentry.
`lib/services/analytics/analytics_config.dart` holds the EU host; the project
API key comes in at build time (`--dart-define=POSTHOG_API_KEY`, passed by
`scripts/build_release.sh` from the environment and by CI from the
`POSTHOG_API_KEY` secret). A build without it - a fork, a debug run - sends
nothing. Autocapture is off across the board.
`errorTrackingConfig.captureFlutterErrors`/`capturePlatformDispatcherErrors` are
on. `$ip` is stripped in a `beforeSend` hook, though the setting that matters is
the project's own "Discard client IP data" toggle in the dashboard.

Independently of PostHog, `ErrorReports` (`lib/services/app/error_reports.dart`)
hooks the same two handlers from `main`, before PostHog starts; PostHog chains
to whatever handler it finds, so both see every error. It keeps the last
reports in shared preferences, so a crash is still there after the restart,
works with analytics off, and sends nothing by itself: Settings → Feedback →
Error reports lets the user mail or share them.

- **Events and property names are closed enums** (`AnalyticsEvent`,
  `AnalyticsProperty`): what is sent has to be readable off one list, both to
  keep the privacy policy's table honest and to stop a hostname reaching
  `capture()` under an ad-hoc key. A debug-only shape check rejects any string
  value carrying `@`, a slash or a newline - a tripwire, not a proof. **The
  policy's §4 tables are written from these two enums**; a name added to either
  without being added there makes the policy wrong.
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
- `AnalyticsService` is the only thing that touches `Posthog()`. `main.dart`
  always calls `init()`, which does nothing unless consent is already granted.
  **`Posthog().setup()` is deliberately not called before consent**, and
  `optOut` does not stand in for it: `setup()` persists a device id, `optOut`
  only gates sending, and `posthog-android` has no config that prevents the
  write. Storing an identifier is what ePrivacy Art. 5(3) asks consent for
  (EDPB Guidelines 2/2023: whether or not it is personal data). So the first
  `setConsent(true)` starts the SDK; `init()` only picks it up on later
  launches. `capture()` is a no-op until then, and swallows errors.
- The consent question is the last step of onboarding, not a standalone dialog;
  the Settings toggle calls the same `setConsent()`, so it works both as the
  answer to a prompt the user missed and as an off switch later.
- **Event retention is the billing plan, and nothing else.**
  `Team.event_retention_months` is denormalised from the billing entitlement and
  read-only. Free is one year, **any** paid plan - including pay-as-you-go,
  which starts at $0 with a card on file - is seven. It cannot be worked around
  in code: PostHog has no timestamp-filtered event deletion, only
  `DELETE /persons/<uuid>?delete_events=true`, which removes *everything* that
  person sent. The policy's §6 has to match the plan.
