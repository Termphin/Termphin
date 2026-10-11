# SSH, connectivity and reconnecting

Transport, host keys, jump hosts, the network monitor, reconnect behaviour and connection quality.

## SSH

`SshSessionManager` (singleton) holds the map of active sessions. What is
deliberately *not* in it lives under `lib/services/terminal/`:
`OscMarkerTracker`/`ReplayWaiter` (`osc_markers.dart` - the in-band channel for
cwd, snippet exit codes and end-of-replay), `AgentProbeCache` (in-memory only, a
probe outliving the process could outlive the binary it was compared against),
and `RemoteMuxCommands` (every agent command plus both shells' quoting rules).
None touches a tab or a session, which is what makes the Windows quoting - the
part that actually goes wrong - testable alone.

Protocol via `dartssh2`; rendering is native Flutter via the `terminal_view`
package, wrapped by the `TerminalPane` widget. `SftpService` is the SFTP file
operations, `LockService` the PIN/biometric lock over `local_auth`. The PIN hash is
PBKDF2 at 20k rounds, chosen for how long an unlock takes rather than against
an attacker - a 4-digit keyspace is not protected by rounds, and 100k held a
correct PIN on screen for seconds on a budget phone; an older record is
rewritten after the unlock, not before it. What slows guessing is
`attemptPin`'s lockout: three free tries, then 30 s doubling to 15 min, kept
in preferences so closing the app does not reset it. A PIN is 4 to 6
digits; its length is stored beside the hash (`pinLength`, 4 when absent,
since every earlier PIN had 4), so the lock screen draws that many dots and
checks on the last digit instead of asking for a confirm tap.

`SshService` is the low-level SSH/SFTP layer. **The cipher proposal is ours, not
dartssh2's default** (`kSshCipherPreference`): the library leads with AES-GCM,
which pointycastle does at ~1.2 MB/s against ~59 for AES-CTR and ~84 for
ChaCha20 - measured, and exactly the ceiling every SFTP transfer used to sit at.
ChaCha20-Poly1305 first, then CTR, GCM last for a server that offers nothing
else. Nothing weaker: CTR is paired with encrypt-then-MAC and CBC stays off the
list.

`disconnect()` never awaits `Socket.close()` directly - it half-closes and
completes when the peer closes back, which a vanished peer never does. The
reconnect path awaits that teardown, so an unbounded wait is a reconnect that
never starts: `_closeSocket()` caps the graceful close at two seconds and then
calls `destroy()`.


## Host key verification

`SshService` passes `onVerifyHostKey`; without it dartssh2 accepts every key it
is handed. Pins live in `KnownHostsStore`, keyed the way OpenSSH keys
`known_hosts` - by address, port **and** key type, since a server legitimately
offers several keys. The record set is sealed with `SecretCipher`: the
fingerprint is public, but a writable plaintext file would let an attacker
replace the pin and turn the check into a rubber stamp.

- **Fails closed.** No prompt to raise means no way to establish trust, so the
  connection does not happen - which is what makes it safe for background paths
  (`_withTemporaryClient`) to pass no prompt.
- `showHostKeyPrompt` (`host_key_dialog.dart`) reaches the root `navigatorKey`
  and is installed onto `SshSessionManager` from `main.dart`, not imported by it
  - the manager stays platform-neutral.
- The pin is keyed against the address actually **reached**, not the profile's
  nominal host; `fallbackHosts` reaches several machines, each with its own key.
- A legitimately rotated key is un-pinned from Settings → Known hosts. The
  mid-connect scare dialog is not where "read the fine print" belongs.
- Time spent in a prompt is handed back to the auth timeout (`_promptedFor` /
  `_awaitAuthenticated`) - that timeout is about an unresponsive server, not
  about a question we asked.

**Keyboard-interactive** (`answerUserInfoRequest`) puts the server's prompts on
screen via `showKeyboardInteractivePrompt`. It used to return blanks, which
locked out every host configured for 2FA/TOTP or PAM passwords. A round with
**no** prompts is still answered silently - Tailscale sends one as an
informational step.

**Jump hosts** (`SshProfile.jumpHostProfileId`) are OpenSSH's `ProxyJump` - a
profile rather than a bare address, because a bastion has its own credentials,
key and host key. `SshService._transportOpener` returns either the plain socket
connector or a `forwardLocal` channel over a bastion session, built **once**
outside the candidate retry loop, so every fallback address is a channel on that
one session. Chains recurse and are cut off at `_maxJumpDepth`. The session with
the target is still end-to-end encrypted and its host key still checked. The
profile form excludes any candidate whose chain comes back to the profile being
edited.


## Connectivity

`NetworkMonitor` reports interface state, not reachability, plus an `onRegained`
signal a parked reconnect waits on. Its cached reading cannot be trusted after a
background stint: a frozen process misses `connectivity_plus` broadcasts, which
are dropped rather than queued, so a device that went offline and came back
reads as permanently offline and parks every reconnect against a comeback that
already happened. `refresh()` re-probes and fires `onRegained` if the reading
flipped; `main.dart`'s resume hook calls it next to `dropDeadSessions()`, and
`SshConnectionNotifier` polls every 20s while a retry is parked. **A park with
no timer and no pending event is the bug to watch for.**

`onHandover` fires when the set of live interfaces changes while online (WiFi
to mobile, one of two dropping out). A socket bound to the address that left
goes silent instead of erroring, so `main.dart` answers it - and every resume -
with `SshSessionManager.probeSessions()`: a ping now, and the link given up
unless something arrives in time - 5s after a resume, where the radio may still
be waking; after a handover 10 round trips clamped to 1.5-5s, since the new
interface is already up. Only agent-backed sessions are probed; on a plain one
a wrong call kills the shell.


## Reconnecting

- **Retries never run out while the failure can pass.**
  `SshConnectionNotifier.reconnectDelay` is 0, 1, 2, 4, 8, 16, then 30s. A
  failure no retry can fix - auth, host key, key, a jump host's config, the
  local-network permission - ends on the error card at once instead.
- **The terminal stays on screen, and nothing else moves.** While
  reconnecting, `SessionView` keeps the last live pane (`_heldFrame`) as it was,
  with `ReconnectingIndicator` in place of the quality pill as the only sign, and
  after a replay attach keeps it over the new pane until that one is ready. No
  dimming, and `TerminalScreen` counts reconnecting as live so the key toolbar
  and dock stay - taking the toolbar away resizes the pane, which the shell
  would redraw for. The pane lives under a `ValueKey(attachId)` in one `Stack`,
  which is what lets both be there at once without losing state.
- **Typing is held, not lost.** `ReconnectInputBuffer` keeps printable text
  only - no Enter, no control key, no escape sequence, a chunk carrying any of
  them dropped whole - and backspace edits what is held. Never while a
  full-screen program has the alt buffer, where plain keys are commands. Sent
  once the terminal is back to show the echo; dropped if the session is not.
- **Resume instead of replay.** The agent (0.12.0+) numbers its raw output and
  ends every replay with `OSC 5383;termphin-offset;<epoch>:<n>`;
  `OutputOffsetCounter` counts on from there into
  `ActiveSessionView.outputPosition`. The epoch is per master, so a position
  kept from a master that crashed or was restored is never read against the
  new one's numbering. A reconnect then attaches with
  `--replay --resume <epoch>:<n>` on the **same** `ActiveSessionView`, so
  the pane keeps listening and gets only what it missed, and `attachId` is not
  bumped. Output is staged until the end marker says which happened: a
  `resume-end` is delivered, a `replay-end` (offset gone, or a master older than
  the flag) replaces the history and remounts as before. Unix only -
  `SshSessionManager.canResume` refuses PowerShell, whose ConPTY re-renders
  output so the counts cannot match. A failed resume leaves the session dropped
  but resumable from the same position, since the position only moves once
  output is delivered.


## Connection quality

`KeepalivePinger` is the keepalive loop and times every round trip into
`SshService.quality` (`ConnectionQuality`); output from the server counts as
hearing from it too. Every 5s while the app is on screen, 15s in the background
(`SshSessionManager.setForeground`, from `main.dart`'s lifecycle hooks). It
never has two of its own pings out, so each round trip is timed from its own
send; the receipts predictive echo asks for share the same in-order reply
queue and do not disturb that. The silence limit depends on what giving up
costs: 45s for a plain session, whose shell dies with the transport; for one
the agent keeps, 30 median round trips clamped to 15-30s, since a wrong call
there only costs a replay. A fresh transport pings once its replay is in
(`measureLatency`), so there is a round trip to scale by from the start.

- **Shown only when bad.** `ConnectionQualityPill` sits over the top-right of
  the terminal - over it, not beside it, since taking room from the pane resizes
  the remote pty. Red "No reply for Ns" once a ping is 5s out with nothing
  heard; amber "Slow connection" when the median of the last five round trips
  is over 300ms (clears at 200). A median, and stall-length replies left out,
  so one hiccup neither raises it nor keeps it up after recovery.
- A tap on the pill opens the connection log (`showConnectionLogSheet`), the
  same sheet the tab's three-dot menu and the dock's `viewLog` action open.
  Just the log: a details sheet with latency numbers and a chart was tried and
  dropped as more than anyone needed.
