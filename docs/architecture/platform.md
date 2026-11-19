# Platform behaviour: background, permissions, shortcuts

Foreground service, iOS suspension, the local network permission and home-screen shortcuts.

## Background execution

`ForegroundNotificationService` runs an Android foreground service
(`flutter_foreground_task`) while sessions are connected, so the process is not
frozen and the sockets survive backgrounding. Holds wake and WiFi locks; no
`TaskHandler` isolate. Wired to `SshSessionManager.activeCount` from `main.dart`
to keep the manager platform-neutral. **Not optional** - a frozen process drops
every socket, so there is no on/off switch; Settings and onboarding offer the
battery-optimisation exemption instead. That and the notification permission are
system-owned, so both render as `PermissionTile` (state read from the system,
trailing Allow/Allowed, tap opens the system screen) - never a switch the app
cannot honour - and both screens re-read on resume. `SystemSettingsChannel.kt`
opens the app's notification settings, the only route left once the one-shot
permission dialog has been answered. `SshSessionManager.dropDeadSessions()` runs
on resume to mark transports that died while frozen.

**iOS is fundamentally different.** There is no equivalent API, and
`ios/Runner/Info.plist` deliberately carries **no `UIBackgroundModes` key at
all**: none of the modes will hold an SSH socket, each requires the app to
actually perform that function, and using one to keep a connection alive is
grounds for App Store rejection. Roughly thirty seconds after the user leaves,
iOS suspends the process and plain SSH sessions drop; the remote agent on the
server is what survives. Settings on iOS replaces the battery tile with
`backgroundSuspended`.

**Neither platform's ongoing-activity surface is used, and both were considered
and dropped.** An iOS Live Activity could only honestly report agent-held
sessions rather than live transports, and would cost a Widget Extension target.
Android's Live Updates (`Notification.ProgressStyle`) are for a user-initiated
activity with a measurable end, which a session has not. `DownloadChannel.kt`
stays on plain `NotificationCompat`. **Do not add either without being asked.**

`LocalNotificationsService` is iOS-only and posts **only** finished or failed
transfers, never sessions - without a foreground service a session notification
would be a claim about nothing. Notification permissions are unified through
`ForegroundNotificationService`'s three methods, which on iOS delegate to it;
that is why the Settings permission row is not hidden there.

`IOSBackgroundTask` over `BackgroundTaskChannel.swift` wraps each public
download entry point (`IOSBackgroundTask.guard`) in a
`UIApplication.beginBackgroundTask` grant - roughly thirty seconds, enough for a
transfer in flight to finish writing. Holding a grant past expiry is what makes
iOS terminate rather than suspend, so `expirationHandler` ends the task even if
Dart never does.


## Local network permission

`LocalNetworkPermission` over `LocalNetworkChannel.kt` handles
`ACCESS_LOCAL_NETWORK`, which `targetSdk = 37` makes load-bearing. Without it
Android 17 drops a socket to a LAN address as a **timeout rather than a
refusal**, indistinguishable from a machine that is off. So the check runs
**before** the candidate loop: dialling a blocked address only buys 30 seconds
of waiting for an answer that cannot come, and `localNetworkBlocked` is raised
straight away. Direct connections only - a jump host's traffic leaves as a
channel on the bastion, so nothing local left the device.

`allOnLocalNetwork` is **all**, not any: a profile whose `fallbackHosts` include
an off-LAN address still has somewhere to go. `isLocalNetworkAddress`
deliberately excludes 100.64.0.0/10 - that is where a VPN like Tailscale puts
its peers, routed over a tunnel rather than the LAN, and
`local_network_permission_test.dart` exists to pin that.

Offered in three places, all `PermissionTile` behind `isEnforced` so nothing
below Android 17 sees it: onboarding, Settings (both on iOS too), and the error card in
`SessionView` - which leads with Allow and dials again the moment it is granted,
demoting Retry to an outline. Nothing is requested unprompted at startup.

iOS has no API for it, so `LocalNetworkChannel.swift` probes instead: it
advertises a Bonjour service (`_termphin._tcp`, listed in `NSBonjourServices`)
and browses for it - finding it means allowed, `PolicyDenied` means refused.
The first probe is what raises the system prompt, so `isGranted` reports false
without probing until `request` has run once (`local_network_asked` in
UserDefaults); a refusal after that comes back `permanentlyDenied`, since iOS
asks only once. That is what puts the row in onboarding and Settings on iOS
too.

The pre-flight check stays Android-only: on iOS reading the state before the
first request would raise the prompt, and dialling the address raises it
anyway. iOS gets `localNetworkUnverified` instead, raised only
after every candidate failed, all were local, and there is no jump host. That is
explicitly a guess - a switched-off machine looks identical - so Retry stays
primary there, beside an outlined button into app settings.


## Home-screen shortcuts

`QuickActionsService` publishes home-screen shortcuts for up to four recent
profiles. Icons differ by platform: Android uses 84 per-colour adaptive
drawables, iOS 12 template imagesets (iOS tints template images itself and
throws the colour away). Both generated from `assets/icons/profile_avatars/` by
`scripts/generate_quick_action_icons.py`.

## Sharing to Termphin

Android only for now; iOS has no share extension yet.

`ShareActivity` takes `SEND`/`SEND_MULTIPLE` and runs **its own Flutter
engine** on `shareMain` (`lib/main.dart` → `runShareApp` in
`lib/screens/share/share_screen.dart`), in the sharing app's task. That is
what makes it behave like sharing to a chat: it opens over the other app, and
`finish()` after the upload lands back there. The main activity and its
sessions are never brought forward.

- **Nothing of `main()` runs there**: no restored sessions, no foreground
  service, no analytics - only `loadAppSettings()` and the `navigatorKey` the
  host key and keyboard-interactive dialogs need. Same process, separate
  isolate, so every singleton is a fresh copy.
- **The PIN still comes first** (`ShareGate`, pinned by
  `test/security/share_lock_test.dart`).
- **Machines only, then SFTP only**: `ShareUploadScreen` opens a bare
  `SshService` + `SftpService`, no shell and no tab, starts the folder picker
  in the home folder, and hangs up when it is popped.
- **Files only.** Text alone gets a message; there is no terminal to type it
  into.
- **Shared files are re-readable.** `ShareChannel` keeps the URIs and opens a
  fresh stream on every `rewind`, so a failed upload or a second machine reads
  the file from the start. The grant lasts as long as the activity.
- **Two copies of `SharedPreferences`.** Each isolate caches its own, so the
  main app reloads them on resume - otherwise a host key accepted in a share
  would be asked about again, or written back out of the known hosts.
