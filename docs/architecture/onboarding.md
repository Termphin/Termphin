# Onboarding, prompts and release notes

The first-run flow, the store review prompt, and the difference between the changelog and the what's-new popup.

## Onboarding and prompts

**Onboarding:** `lib/screens/onboarding_screen.dart`, gated by
`OnboardingService` in `_AppGate` - shows once, before the lock screen, on a
fresh install. Four pages: welcome, "do you have a server?", permissions,
analytics consent. The permissions page re-reads on resume because the system
dialogs report nothing back.

- **The server question is the point of it.** In September 2026 about 70% of
  new users never added a machine: most had nothing to connect to, or expected
  a terminal on the phone itself, and the old flow ended on an empty list with
  one button. "Yes" closes onboarding straight into the machine form; "Not yet"
  opens `ServerGuideList` in place. The same guide is behind "No server yet?"
  on the empty machine list.
- **The welcome page is the real logo and one sentence**, not a generic icon.
- **The empty machine list takes `user@host`** - or a pasted `ssh -p 2222
  user@host`, or an `ssh://` link - through `parseSshTarget`, which steps over
  ssh's flags and refuses anything after the host, and opens the form filled in.
- **"Test connection" in the machine form** runs `SshSessionManager
  .testConnection` on the unsaved fields: the same temporary-client path, host
  key prompt and failures a first session gets, then disconnects. The form
  reaches it through `connectionTestProvider` so tests can stand in for the
  network. A name is optional; left empty the machine takes the host's.
- **A key is made from the machine form** ("Create a new key" in the SSH
  key section): the full `KeyFormScreen`, any type or an import, named after
  the machine. `showKeyFormScreen` completes with the key it made and the form
  picks it; the public half is shown through `showPublicKeyDialog` - a new key
  is useless until it is in the server's `authorized_keys`.
- **A new machine has no sign-in method until one is picked.** It used to
  default to password whenever a username came in with a link or a quick add,
  which put people on a method they never chose. Save and "Test connection"
  ask for the choice instead.
- **No remote agent page.** The agent is on by default and switched in
  Settings; a toggle nobody had a reason to flip yet was a step, not a choice.

**Store review prompt:** `ReviewPromptService` over `in_app_review`. The store's
own dialog is the only thing ever shown - there is deliberately no "do you like
Termphin?" in front of it, because filtering who gets asked by how they feel is
against store policy and the API returns nothing to branch on. Gates, all
device-local: five successful connections, three days since the first, and
either never asked or 120 days plus a new version since the last. A request that
throws burns no cooldown. It fires from `_AppShellState._checkWhatsNewThenReview`
and only when the what's-new modal had nothing to show - the home screen gets
one interruption, not two, and never over a live terminal. Settings → About has
a "Rate Termphin" row straight to the listing instead, since the in-app dialog
is quota'd. Neither path is testable on a debug build.


## What's new vs the changelog

Two artefacts, deliberately not one. Generating the popup from the changelog is
what produced a wall of bullet points nobody read.

- `assets/release_notes.yaml` is the changelog proper: every version, Keep a
  Changelog categories, fixes and all. It feeds `ReleaseNotesService` →
  `ReleaseNotesScreen` and the release workflow.
  The website copies the file as it is, so anything added
  ships verbatim to the public changelog page - which is why highlights are not
  in here.
- **`version: "Unreleased"` is where work goes as it lands.** Nothing renders
  it: `isReleasedVersion` is "a dotted number `compareVersions` can order", and
  `ReleaseNotesService`, `WhatsNewService` and the website's changelog page
  all drop what fails it. It is a parsing rule,
  not a rendering one - `compareVersions` is `int.parse`, so an entry left in
  front of it throws rather than sorting oddly, which is why the filter sits at
  the read. Give it its real number at release time and it appears everywhere.
  Both yaml files take the marker, and there is only ever one such entry.
- `assets/whats_new.yaml` is the popup: hand-written, only ever new features.
  Each highlight is `id` + `title` + `body` (prose) + optional `image`. **A
  version with no `highlights` block means no popup at all**, and most versions
  are meant to have none - a release is not owed an announcement. **Do not add a
  block, or flag a missing one as a gap, without being asked.**
- What has been shown is tracked **per highlight id**, not per version
  (`kSeenWhatsNewIdsPrefsKey`) - which is what makes adding a highlight to an
  older block, or re-dating a release, behave sensibly. Changing an id shows
  that page again; that is the only way to re-announce something. **An id is one
  announcement, not one yaml row**: repeating it under a later version means
  "same thing, reworded", and `_collapseById` folds repeats into one page with
  the newest wording.
- On the first run where the key is absent - fresh install, or an upgrade from a
  build predating the file - every *already-released* id is seeded as seen and
  nothing is shown. Seeding is limited to `version <= currentVersion`, so a
  highlight written ahead of its release is held back rather than buried.
  `pendingSince` returns oldest release first, and `app.dart` calls `markSeen`
  with the list it actually showed.
- `WhatsNewModal` is one highlight per page in a carousel.
  `barrierDismissible: false` - an interstitial with a button should not be
  skippable by a stray tap. The page height is a constant, not measured: a
  carousel hands every page the same constraints, so a content-driven height
  would be set by the longest body and make the card jump. Below
  `_kImageMinHeight` of window the illustration is dropped rather than shrunk. A
  missing image asset degrades to a text-only page.
- `compareVersions` (`lib/services/app/version_compare.dart`) is shared by both
  services - two copies would only agree until one was edited.
