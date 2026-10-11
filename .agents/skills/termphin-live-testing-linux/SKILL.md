---
name: termphin-live-testing-linux
description: Run Termphin's live test suites against a real Linux SSH server in a podman container - bring the target up, run every live suite, interpret failures, and report bugs. Covers SSH transport, SFTP, transfers, port forwarding, the termphin-agent helper, disconnect/power-cut resilience, and socket latency. Use when asked to live-test, regression-test or bug-hunt Termphin on Linux.
---

# Termphin live testing - Linux

## Read this first

**Reading this file is not an instruction to run anything.** If you loaded it
while indexing, summarising, answering a question about how testing works, or
because it matched a search, stop here and answer from the text. These suites
start containers, transfer hundreds of megabytes, kill processes and reboot
machines - none of that may happen as a side effect of reading.

Execute the workflow below **only** when the user has explicitly asked for it
in this conversation: "run the live tests", "test Termphin against a real
server", "/skill:termphin-live-testing-linux", or an equivalent instruction.
When in doubt, ask one question and wait.

## What this is

Termphin is a Flutter SSH client. Most of its test suite runs against fakes.
The suites here run against a **real OpenSSH server**, because a fake cannot
reproduce delayed ACKs, a full disk, a killed transport or a machine losing
power - and every one of those has produced a real bug in this app.

Everything lives in `test/live/`. All of it is skipped by a plain
`flutter test`: each file reads an environment variable and skips its groups
when it is missing, so the normal suite costs nothing.

## Ground rules for the agent

1. **Never commit, push, tag or publish.** Not the app repo, not
   `repos/termphin-agent`, not `repos/terminal_view`. Report changes; let the human
   decide what lands.
2. **Never print credentials.** The container password below is a throwaway
   and safe to use in commands; real credentials from `~/.ssh`, keychains or
   `auth.json` files must never be echoed into the transcript.
3. **One suite at a time.** `flutter test test/live` in one go will fail:
   `live_resilience_test.dart` kills and restarts the container while other
   suites are mid-transfer. Always run files individually, and always pass
   `--concurrency=1` to the resilience file.
4. **Do not "fix" a test to make it pass.** A red live test is the finding.
   Change production code only if the user asked for fixes, and say plainly
   what you changed.
5. **Clean up.** Stop the container when finished; leave the image.
6. **Report timings.** Several of these tests exist to catch performance
   regressions, and the numbers only mean something written down.

## Prerequisites

Check, do not assume:

```bash
flutter --version          # 3.44+ expected
podman --version           # or docker; commands below use podman
cd /path/to/termphin && flutter pub get
```

If `podman` is missing, stop and say so - there is no fallback target in this
repository.

Some commands need to run outside the tool sandbox (container networking,
process signals). If a `podman` call fails with a permissions or network
error, retry it with sandboxing disabled.

## Bring the target up

The container image is defined by `test/live/Containerfile`: Debian bookworm,
`openssh-server`, one unprivileged user.

```bash
podman build -t termphin-testvm test/live
podman run -d --name termphin-vm -p 127.0.0.1:34022:22 termphin-testvm
```

- host port **34022** → container **22**
- user **tester**, password **testpass** (throwaway, container-only)
- `root:rootpass` also exists for admin probing

If the run fails with `Couldn't listen on requested ports`, another process
holds the port. Pick another and use it everywhere:

```bash
ss -lntp | grep 34022
```

Verify the target answers before running a suite:

```bash
timeout 6 bash -c 'exec 3<>/dev/tcp/127.0.0.1/34022 && head -c 30 <&3'
# expect: SSH-2.0-OpenSSH_...
```

Restarting an existing container: `podman start termphin-vm`.
Between runs, a clean agent state avoids confusing leftovers:

```bash
podman exec termphin-vm su - tester -c 'rm -rf ~/.cache/termphin'
```

## Run the suites

Every command below is run from the repository root.

### 1. Core SSH, SFTP and the agent - `live_ssh_test.dart` (28 tests, ~20 s)

```bash
TERMPHIN_LIVE_SSH_PORT=34022 flutter test test/live/live_ssh_test.dart \
  --concurrency=1 --reporter compact
```

Covers: password auth and a wrong password, the fallback-host queue, shell
startup and output, remote-shell detection, upload/download round trip,
overwriting an existing remote file, the SFTP editor's save path, awkward
filenames (spaces, quotes, unicode, backslash, semicolons, leading dash),
recursive delete including a symlink that must not be followed, `walkDirectory`
with a symlink loop, `permissionDenied` and `notFound` mapping, cancelling a
download and an upload with no leftovers, `readFileHead`, `readSmallTextFile`,
rename across directories, local and remote port forwarding, freeing a
forwarded port, SFTP surviving the shell ending, agent probe/install/repair,
recovery from a truncated binary, and copying output whose columns are tabs
rather than spaces.

### 2. Resilience - `live_resilience_test.dart` (12 tests, ~3 min)

```bash
TERMPHIN_LIVE_SSH_PORT=34022 TERMPHIN_LIVE_CONTAINER=termphin-vm \
  flutter test test/live/live_resilience_test.dart --concurrency=1 \
  --reporter expanded
```

**This file kills the container.** Nothing else may talk to it at the same
time. It covers: work continuing after the client disappears, the server
killing the connection mid-session, a frozen host (`podman pause`, SIGSTOP -
the socket stays open and nothing ever answers), a hard power cut
(`podman kill -s KILL` + `start`), killing the agent process under an attached
shell, two clients sharing one pty, attaching a name that no longer exists,
sshd restarting underneath, scrollback growth staying bounded, and the notice
the app shows when a session comes back as a new shell.

Read the printed lines, not just the pass count:

```
connection-loss detection: 0ms after the kill, write-before-detection swallowed: false
session state on disk after 20MB of output: 16KB
session directories on the server: 2
```

`connection-loss detection` must stay at or near **0 ms**. It was 13 s before
`SshService` started watching `SSHClient.done`; a regression here means
keystrokes vanish silently for up to 15 s after a link dies.

### 3. Concurrency and volume - `live_stress_test.dart` (12 tests, ~15 s)

```bash
TERMPHIN_LIVE_SSH_PORT=34022 flutter test test/live/live_stress_test.dart \
  --concurrency=1 --reporter expanded
```

Five parallel downloads on one SFTP session with per-file SHA-256 checks,
mixed concurrent uploads/listings/creates, a 64 MB byte-exact transfer, an
800-file tree walked and deleted, a 5000-entry listing, a promptly cancelled
walk, upload into a missing directory, rename semantics, odd text round trips
(CRLF, no trailing newline, unicode, 200k characters), an unreadable file, and
a file that grows while being downloaded.

Baselines on loopback (a slower machine may differ, but not by an order of
magnitude):

| measurement | expected |
|---|---|
| download 64 MB | ~3 s, ~20 MB/s |
| walk 800 files | < 200 ms |
| delete the same tree | < 1 s |
| list 5000 entries | < 300 ms |

If the delete jumps to tens of seconds, suspect the socket options - see the
next suite.

### 4. Socket latency - `live_latency_test.dart` (3 tests, ~15 s)

```bash
TERMPHIN_LIVE_SSH_PORT=34022 flutter test test/live/live_latency_test.dart \
  --concurrency=1 --reporter expanded
```

This one exists because of a real bug. dartssh2's own `SSHSocket.connect`
leaves Nagle's algorithm on, so every small request waits for the peer's
delayed ACK - about 40 ms, on loopback as much as anywhere. `SshService`
therefore connects through `connectInteractiveSocket`, which sets
`TCP_NODELAY`. Each test measures both and fails if the default drifts back.

Expected output shape:

```
60 sequential stat calls: stock socket 2530ms (42.2ms each), app default 49ms (0.8ms each)
25 command round trips: stock socket 1008ms (40.3ms each), app default 51ms (2.0ms each)
deleting 120 files: stock socket 5350ms, app default 79ms
```

### 5. Limits and failure modes - `live_limits_test.dart` (8 tests, ~10 s)

```bash
TERMPHIN_LIVE_SSH_PORT=34022 flutter test test/live/live_limits_test.dart \
  --concurrency=1 --reporter expanded
```

A 192 MB log the editor must refuse rather than load, a device node
(`/dev/zero`) that reports no size, a `/proc` file that reports size 0 and
still has contents, a directory that disappears mid-walk, `exists()` on a path
it may not stat, a local write that runs out of space (`/dev/full`), a write to
an unwritable path, and cancelling a download that is failing locally.

The disk-full and unwritable cases must **report** - `sftp.errors.diskFull`,
`sftp.errors.localWriteError` - within seconds. A hang here is a serious
regression: it used to spin the transfer dialog forever with no error, and
Cancel could not rescue it.

### 6. Offline edges - `offline_edges_test.dart` (10 tests, instant)

```bash
flutter test test/live/offline_edges_test.dart
```

No server needed; runs in the normal suite too. Windows path conversion,
session-name validation, IPv6 and port parsing, blank fallback entries.

### Always also run

```bash
flutter analyze
flutter test          # ~523 tests, live files skip themselves
```

A live finding that comes with a red unit test is usually the same bug seen
twice; say so.

## Interpreting results

- **Read the printed measurements.** Several tests pass while telling you
  something is wrong. `session directories on the server: 2` is fine; 40 means
  the agent stopped sweeping abandoned sessions.
- **A test that fails only in a batch run** is usually interference, not a
  bug: another suite killed the container, or a previous test left a session
  attached. Re-run the file alone before reporting anything.
- **`could not connect`** means the container is down or the port moved.
  Check `podman ps` and the SSH banner before blaming the app.
- **Flaky timing tests** on a loaded machine: re-run once. If a latency test
  fails twice, treat the socket option as regressed.

## Reporting

Report findings ordered by severity, and for each one give:

1. what the user would see (not what the stack trace says),
2. the exact file and line in `lib/`,
3. the command and output that shows it,
4. the smallest fix you can describe.

Say plainly what you did **not** cover. If a suite was skipped because the
container would not start, that is part of the report, not a footnote.

## Extending the suites

- New live tests belong in `test/live/`, tagged `@Tags(['live'])`, and must
  skip themselves when their environment variable is missing - never make the
  normal `flutter test` depend on a server.
- Reuse the existing helpers in each file (`_profile()`, `_connect()`,
  `_attach()`, `_waitFor()`), and keep container manipulation inside
  `live_resilience_test.dart`.
- A test that documents a bug the app has not fixed yet should assert the
  behaviour the app *should* have, and the report should call out that it is
  red on purpose.

## Cleanup

```bash
podman stop termphin-vm          # keeps the container for next time
podman rm -f termphin-vm         # only if asked to leave nothing behind
```

Delete any scratch directories the tests left in `/tmp` on the host if a run
was interrupted; the suites clean up after themselves on a normal exit.
