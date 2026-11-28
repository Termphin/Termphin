# Live presence

Which machines are online and which sessions they hold, without opening SSH.
A Pro feature, switched on per machine.

## The pieces

| Where | What |
|---|---|
| `termphin-agent` (`src/presence.rs`) | Each session process reports the server's sessions when it starts, every five minutes while it runs and when it ends, and `termphin-agent presence` reports from the user's crontab every five minutes and at boot: `POST https://rt.termphin.dev/v1/agent` through `curl`, the relay key in the body. Every report says online; the machine goes offline when reports stop for 12 minutes |
| `rt.termphin.dev` | Passes each report on to the account's apps over a WebSocket; the machine counts as online for 12 minutes after a report |
| `lib/services/realtime/` | `LivePresence` keeps the WebSocket, `presence_keys.dart` the per-server keys, `presence_state.dart` opens what the agent sealed |
| `lib/providers/live_presence_provider.dart` | When the connection runs, which relay key belongs to which machine, and which reported sessions become session rows |

## Keys

The backend only routes what it is given; the session list is sealed end to
end.

- `PushService.setUpMachine` (called by `ensureOnServer` and `setMachine`) -
  the same step that gives a machine its relay key - also writes
  `~/.config/termphin/presence` (`<url> <key>`) when live status is on and the
  server has none, and reads back whichever key is there. The first device to
  set a machine up makes the key; every device that connects to it later
  learns the same one. It is kept per profile in `PresenceKeyStore`, sealed
  with `SecretCipher`.
- The agent seals `{"v":1,"t":…,"sessions":[…]}` with AES-256-GCM, additional
  data `termphin-presence:v1:<relay key id>`, in the layout `aead.dart` opens.
  `presence_state_test.dart` opens the same vector `termphin-agent`'s
  `known_vector_matches_the_app` produces.
- With sync on, the keys travel with the machines as `presenceKey` records,
  sealed with the sync key like everything else synced
  (`StorageSyncLocal`): a device signed in to the account reads a machine's
  sessions before it ever connected to it. Without sync a device that has
  never connected to a machine sees it online but not its sessions, which
  `SyncNeededTile` says under the switch. Neither the backend nor Firebase
  can open a key.

## Crontab

On a POSIX server `ensureOnServer` also adds two lines tagged
`# termphin-presence` to the user's crontab (`presenceCronInstallCommand`),
so a machine with no session still reports. The current crontab is read and
written back with the lines appended; when it cannot be read for a reason
other than there being none, nothing is written. Turning the machine's
notifications off removes exactly those lines. Windows has no crontab and
shows online only while a session runs.

## The switches

Every machine starts with nothing on. The bell beside a machine's menu
(`MachineProButton`) switches its two features one by one: notifications and
live status. A switch counts at once on the account - the machine's relay
key carries `notify` and `live` (`RelayKeyStore.setSwitches`), which the
relay and the realtime backend read with the key. Only the switch flipped is
written (`MachineSwitchChange`), so flipping one never decides the other; a
key with both off stays until the server is cleaned up. The change is then set
up on the server over a quick connection that asks the user nothing, gives up
after eight seconds to connect and thirty to finish
(`PushService.setMachine`, `SshSessionManager.withQuietClient`).

A key from before the switches existed carries neither. It reads the way the
backend treats it - live on, notifications as the machine's earlier
`serverNotifications` - and its next connect settles each switch from the
server (`resolveMachineSwitches`): notifications off when its relay file is
quiet, live on when it holds a presence key. A server that cannot be asked
settles nothing; a guess would switch something off for good. Live status
also puts the agent there when it is missing, so the machine shows before
its first session. When the quick connection does not get through, the
switch waits in `PushService.pendingMachines` and the machine's next connect
finishes it (`setUpMachine`).

What a machine should do is the pending switch flipped here, else its key's
switches, else nothing (`machineSwitchesFor`). A key from before the switches
existed counts as notifications on and, on its next connect, is replaced by
one that names the machine and carries them.

The bell is the only place a machine's switches live. Termphin Pro's screen
lists the phones and tablets that get notifications
(`notifyPrefs/{installId}.enabled`, any device can switch them).

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

When a master from 0.20.0 names its version, `SshSessionManager` types
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

### A program that says what it is doing

AI coding agents - Claude Code, Codex, Amp, goose, Qwen Code, opencode and
more - report their own state over the OSC 7501 Program Status Protocol: idle,
working, blocked on the user (for a permission, a question or a sign-in, with
one line saying what), done or failed. The master stands in for the terminal
the protocol talks to (`status.rs` in the agent): it answers the support query
some agents send before reporting - Claude Code among them - keeps the records,
and turns a program becoming blocked, done or failing into its own
notification, as `quiet` (blocked) or `finished` (done, failed), so the
user's switches for those two kinds and for quoting the line hold for it. A
finished turn quotes the last two sentences the agent said (`last_sentences`,
about 180 characters); one reported bare waits a moment and a half for the
same moment told with words - from a hook set up by hand - before the
master reads them from the transcript instead. On Windows the pseudo console drops
an escape sequence written to its input, so the support reply is typed in
as win32-input-mode key presses instead. A
program that reports this way is never guessed at from silence, and the
notifications it also sends the classic way (OSC 9, 777, 99) are not relayed
twice. Its state travels as the status line's seventh field and the
activity's `program` in presence; `SessionActivityLine` shows "Claude Code
needs your permission · approve Bash", the program's own words hidden with
`anonymizeProvider` on, since they can name a host or a path.

The app changes nothing outside its own files. A finished turn quotes the
agent's last reply - from its own report when it gives one (Antigravity
does), otherwise read from the transcript Claude Code or Codex keeps
(`insight.rs`), only ever read - and names the commands it started through a
shell that are still running ("Still running: npm run dev"); what it had
running at rest, its MCP servers, is left out, and a server started straight
by the agent rather than through a shell never counts. tmux drops OSC 7501;
for an agent there, or one too old to report, `termphin-agent hooks
install` puts hooks into Claude Code's and Codex's own settings, by hand
only. A hook finds its session by `TERMPHIN_SESSION_ID`, or by its own
ancestors and the `shell_pid` each master records, so a renamed session or
one whose master was upgraded in place still works. An earlier build of the
app wrote those hooks itself; `setUpMachine` takes out the ones it wrote, once.

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

- Only machines with live status switched on, since the relay key is what
  the agent authenticates with.
- Windows machines without a session show offline (no crontab).
- Device presence (which of the user's devices have the app open) is in the
  protocol but not shown yet.
- The desktop sidebar's session rows do not show attached devices yet.
