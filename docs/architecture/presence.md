# Live presence

Which machines are online and which sessions they hold, without opening SSH.
A Pro feature, on machines with server notifications on.

## The pieces

| Where | What |
|---|---|
| `termphin-agent` (`src/presence.rs`) | Each session process reports the server's sessions when it starts, every five minutes while it runs and when it ends, and `termphin-agent presence` reports from the user's crontab every five minutes and at boot: `POST https://rt.termphin.dev/v1/agent` through `curl`, the relay key in the body. Every report says online; the machine goes offline when reports stop for 12 minutes |
| `termphin-realtime` (private repo) | Verifies the relay key against `relayKeys/{id}` like the relay function, keeps each server online for 12 minutes per report, and pushes every change to the account's apps over a WebSocket |
| `lib/services/realtime/` | `LivePresence` keeps the WebSocket, `presence_keys.dart` the per-server keys, `presence_state.dart` opens what the agent sealed |
| `lib/providers/live_presence_provider.dart` | When the connection runs, which relay key belongs to which machine, and which reported sessions become session rows |

The wire protocol and the backend's threat model live in the backend
repository's `docs/protocol.md` and `docs/security.md`.

## Keys

The backend only routes what it is given; the session list is sealed end to
end.

- `PushService.ensureOnServer` - the same step that gives a machine its relay
  key - also writes `~/.config/termphin/presence` (`<url> <key>`) when the
  server has none, and reads back whichever key is there. The first device to
  set a machine up makes the key; every device that connects to it later
  learns the same one. It is kept per profile in `PresenceKeyStore`, sealed
  with `SecretCipher`.
- The agent seals `{"v":1,"t":…,"sessions":[…]}` with AES-256-GCM, additional
  data `termphin-presence:v1:<relay key id>`, in the layout `aead.dart` opens.
  `presence_state_test.dart` opens the same vector `termphin-agent`'s
  `known_vector_matches_the_app` produces.
- Neither the backend nor Firebase holds a key: a device that has never
  connected to a machine sees it online but not its sessions.

## Crontab

On a POSIX server `ensureOnServer` also adds two lines tagged
`# termphin-presence` to the user's crontab (`presenceCronInstallCommand`),
so a machine with no session still reports. The current crontab is read and
written back with the lines appended; when it cannot be read for a reason
other than there being none, nothing is written. Turning the machine's
notifications off removes exactly those lines. Windows has no crontab and
shows online only while a session runs.

## When it runs

`LivePresenceController` wants the connection while an account with Pro is
signed in and - on a phone - the app is in front; a desktop keeps it in the
background. The app gate tells it about the foreground. A dropped connection
returns after a jittered backoff up to a minute; one closed for no Pro, a
revoked account or a protocol error stays closed until wanted again. The
token is renewed with `reauth` five minutes before it expires.

## Rows

A session that appears in a report and is not on screen becomes a session row
through `adoptRemoteSession`, as "Load sessions" does. Only sessions new since
the last report are added, so a row the user closed does not come back while
the session lives on. A session the report no longer lists loses its row
(`pruneReportedSessions`) unless this device is connected to it.

The machine's avatar shows the green dot while it is online
(`ProfileAvatar.online`); the green ring around it still means this device
holds a connection.

## Who is attached

When a master from 0.19.4 (shipping as 0.20.0) names its version, `SshSessionManager` types
`ESC ] 5386;device;<install id>;<kind>;<base64url name> BEL`
(`presenceDeviceAnnouncement`, built in `main.dart`: the host name on a
computer, the kind of device elsewhere). The attach client takes it out of
the input and hands it to the master, which lists each client's device as a
fifth field of `list` and in its sealed reports, sent as soon as a device
attaches or leaves. `AttachedDevices` draws the other devices on the
session's row as overlapping circles; this device is left out, and with
`anonymizeProvider` on only the kind is read out. A circle names a device,
never a person: nothing verifies what a device says about itself - anyone
with a shell on the server could claim any device - so no account picture is
shown. A person's avatar comes with teams, once each member's devices sign
what they say.

## What a session is doing

Every two seconds the master works out the session's activity
(`track_activity` in the agent): idle when the shell has the terminal,
working while the program wrote something in the last eight seconds,
waiting when it worked for twenty seconds or more, went still and waits for
keys or asks something - the condition the "went quiet" notification uses -
and running otherwise. The program is named by `command_label`, as in
notifications, so nothing after its first option shows. A change is
reported at once and carried in the status line's sixth field.
`SessionActivityLine` puts it under the session's name, the waiting state in
the warning colour; with `anonymizeProvider` on only the state shows. Linux
and macOS only.

## Restart

A master stopped by a signal - the system shutting down - keeps its session
directory for restoring and reports it as `restorable`; when the system is
shutting down (`/run/nologin`) or no other session is left, that report says
offline, so the dot goes out at once rather than when the lease lapses (best
effort, two seconds). Every report also lists the directories with no master
as restorable, so after a reboot the cron line keeps their rows: the
controller never prunes a listed session, and `SessionActivityLine` says
"Restores when opened". Unix only.

## Known gaps

- Only machines with server notifications on, since the relay key is what
  the agent authenticates with.
- Windows machines without a session show offline (no crontab).
- Device presence (which of the user's devices have the app open) is in the
  protocol but not shown yet.
- The desktop sidebar's session rows do not show attached devices yet.
