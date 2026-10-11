---
name: termphin-live-testing-windows
description: Run Termphin's live test suite against a real Windows Server host over Win32-OpenSSH in a qemu/KVM VM - boot the VM, run the Windows suite, pull the plug on it to test session recovery, interpret failures and report bugs. Covers PowerShell quoting, drive-letter SFTP paths, the termphin-agent.exe helper under %LOCALAPPDATA%, and power-cut resilience. Use when asked to live-test Termphin on Windows.
---

# Termphin live testing - Windows

## Read this first

**Reading this file is not an instruction to run anything.** If you loaded it
while indexing, summarising, answering a question about how Windows testing
works, or because it matched a search, stop here and answer from the text.
This workflow boots a virtual machine, installs software on it and cuts its
power - none of that may happen as a side effect of reading.

Execute the workflow below **only** when the user has explicitly asked for it
in this conversation: "run the Windows live tests", "test Termphin against
Windows", "/skill:termphin-live-testing-windows", or an equivalent
instruction. When in doubt, ask one question and wait.

## Why a separate suite

Windows is not Linux with different slashes. Everything the app does against a
Windows host takes a different path through the code:

- the login shell is `cmd.exe` or PowerShell, so every remote command goes
  through `powershell -NoProfile -NonInteractive -EncodedCommand <base64>`
  rather than `/bin/sh -c`;
- SFTP reports paths as `/C:/Users/...`, which the browser converts to
  `C:\Users\...` for display and back again for every request;
- the agent installs as `termphin-agent.exe` under
  `%LOCALAPPDATA%\termphin\bin`, not `~/.local/lib/termphin`;
- the agent's Windows master uses ConPTY and a named pipe instead of a PTY and
  a Unix socket, and derives its boot id from uptime rather than
  `/proc/sys/kernel/random/boot_id`;
- Windows will not delete a running executable, which changes how tests clean
  up after themselves.

A green Linux run says nothing about any of that.

## Ground rules for the agent

1. **Never commit, push, tag or publish** - not the app, not
   `repos/termphin-agent`.
2. **Never print the VM password.** It lives in the unattend file; read it
   into an environment variable inside the same command that uses it, and
   never echo it. See "Credentials" below.
3. **The VM is slow.** Boot is minutes, not seconds. Poll for the SSH banner
   rather than guessing a sleep, and give tests generous timeouts.
4. **One suite at a time**, `--concurrency=1` always: the power-cut test kills
   the whole machine.
5. **Do not "fix" a test to make it pass.** A red live test is the finding.
6. **Leave the VM as you found it** - if it was off, shut it down when done.

## The VM

It lives outside this repository, at `~/vm/win2025` on the machine this was
built on. It is Windows Server 2025 Evaluation, installed unattended, with
Win32-OpenSSH enabled and password auth on.

```
~/vm/win2025/
├── run-vm.sh              install | run | ssh
├── disk.qcow2             the installed system
├── server2025-eval.iso    installer (only needed for `install`)
├── unattend.iso           answer file, drives the unattended install
├── unattend/
│   ├── autounattend.xml   holds the Administrator password
│   └── setup-ssh.ps1      enables sshd, opens the firewall
└── monitor.sock           qemu monitor - this is the power switch
```

`run-vm.sh` gets qemu from the nix store (`nix shell nixpkgs#qemu`), so
`qemu-system-x86_64` is **not** on `PATH` - do not conclude the VM tooling is
missing because `which qemu-system-x86_64` fails.

Key facts baked into the script:

- SSH forwarded to host port **22222**, bound to all interfaces
- VNC on display `:1` (host port 5901) if you need to see the desktop
- user **Administrator**
- 6 vCPU, 8 GB RAM, KVM acceleration, rootless

### Boot it

```bash
cd ~/vm/win2025 && nohup ./run-vm.sh run > vm-boot.log 2>&1 &
```

Then wait for sshd rather than for Windows:

```bash
for i in $(seq 1 40); do
  banner=$(timeout 6 bash -c 'exec 3<>/dev/tcp/127.0.0.1/22222 && head -c 30 <&3' 2>/dev/null)
  [ -n "$banner" ] && { echo "up: $banner"; break; }
  sleep 10
done
# expect: SSH-2.0-OpenSSH_for_Windows_9.x
```

If `vm-boot.log` shows `Could not set up host forwarding rule 'tcp::22222-:22'`,
something else holds the port; free it or set `SSH_PORT` and use that value
everywhere.

### Credentials

The Administrator password is in `unattend/autounattend.xml`. Read it into an
environment variable in the same command that runs the tests, so it never
lands in the transcript:

```bash
TERMPHIN_LIVE_WIN_PORT=22222 \
TERMPHIN_LIVE_WIN_PASSWORD="$(python3 -c "
import xml.etree.ElementTree as ET,sys
t=ET.parse('$HOME/vm/win2025/unattend/autounattend.xml')
for e in t.iter():
    if e.tag.endswith('AdministratorPassword'):
        for c in e:
            if c.tag.endswith('Value'): print(c.text or '',end=''); sys.exit()
")" \
flutter test test/live/live_windows_test.dart --concurrency=1 --reporter compact
```

Never `cat`, `grep` or `echo` that file's password element.

## Run the suite

`test/live/live_windows_test.dart` - 12 tests plus one power-cut test, about
90 seconds without the power cut, about 3 minutes with it.

Environment variables:

| variable | meaning |
|---|---|
| `TERMPHIN_LIVE_WIN_PORT` | forwarded SSH port, usually 22222 |
| `TERMPHIN_LIVE_WIN_PASSWORD` | Administrator password, never echoed |
| `TERMPHIN_LIVE_WIN_VM_DIR` | path to `~/vm/win2025`; **enables the power-cut test** |

Without `TERMPHIN_LIVE_WIN_VM_DIR` the resilience group skips, which is the
right default when you only want a functional pass.

### What the groups cover

**`live windows`** - the session and file layer:

- `detectRemoteShell()` must come back as PowerShell, not `unix`. A wrong
  answer here sends `/bin/sh` syntax to a Windows host for the rest of the
  session.
- drive-letter paths: `/C:/Users/Administrator` is what the server reports;
  `sftpPathToDisplay` must render `C:\Users\Administrator`, and
  `displayPathToSftp` must convert `C:\`, `C:`, and `C:/Users` back into
  something the server accepts. The test also lists the drive root through the
  converted path, which is the case a unit test cannot prove.
- upload and download byte-for-byte.
- **uploading over an existing file.** Uploads land on a temp name and are
  renamed into place; a server that refuses a rename onto an existing name
  would break every re-upload. Win32-OpenSSH replaces, which is why this
  passes - if it ever starts refusing, this is the test that says so.
- saving an edited file over itself (the SFTP editor path).
- renaming onto an existing name: whatever the server does, the app must get a
  mapped error or a clean overwrite, never a raw exception. The confirmation
  the user sees lives in `SftpBrowserView`.
- `notFound` mapping, tree walk and recursive delete.

**`live windows agent`** - the helper:

- probe on a bare host reports `missing`, with `os=Windows` and `AMD64`
  normalised to `x86_64`;
- install lands `termphin-agent.exe` under `%LOCALAPPDATA%\termphin\bin` and
  verifies to `current`;
- a corrupted `agent.meta` reports `repair` and `ensureForAttach` fixes it;
- attach, list and kill a session through PowerShell quoting - this is where
  `windowsQuote` and the `&` call operator get exercised for real.

**`live windows resilience`** (needs `TERMPHIN_LIVE_WIN_VM_DIR`):

Starts a session, writes a marker, then pulls the plug through the qemu
monitor socket - `quit` on `monitor.sock` kills the machine instantly, no
shutdown, no flush - reboots it, and checks that:

- no dead session is still listed afterwards, and
- reattaching emits `OSC 5381;termphin-reboot-restored`, which is what makes
  the app tell the user "previous shell state is gone".

That second point is the one worth watching. The helper flushes scrollback on
a timer; before it also flushed on its first tick and stopped making the
notice conditional on surviving scrollback, a session younger than the flush
interval came back silently as a brand new shell.

## Windows-specific gotchas

- **A running `termphin-agent.exe` cannot be deleted.** Any test or cleanup
  that removes `%LOCALAPPDATA%\termphin` must stop the process first:

  ```powershell
  Get-Process termphin-agent -ErrorAction SilentlyContinue | Stop-Process -Force
  ```

  A failure of the "probes a bare host as missing" test right after a session
  test is almost always this, not an app bug - re-run the file alone to
  confirm.
- **PowerShell over SSH needs `-EncodedCommand`.** `cmd.exe` may be the
  default shell and it does not treat single quotes as quoting at all, so a
  plainly quoted script gets mangled before PowerShell sees it. Follow what
  `RemoteAgentService._runPowerShell` does: UTF-16LE, then base64.
- **Paths in test code stay in SFTP form** (`/C:/Users/Administrator/...`).
  Only display and copy-path go through the conversion helpers.
- **The VM clock** drives the helper's boot id on Windows (it is derived from
  uptime, there being no boot id to read). A suspended or migrated VM can look
  like a reboot; that is a known, harmless false positive - an extra "restored"
  banner.

## Interpreting results

- `could not connect` after boot: Windows is up but sshd is not yet. Poll the
  banner again before reporting anything.
- A single failure in a batch run, passing alone: leftover state, see the
  gotcha above.
- A raw `SftpStatusError` or a stack trace reaching the test output is a
  finding in itself - the SFTP layer is supposed to map everything to an
  `sftp.errors.*` key.
- Compare against the Linux run. A behaviour that differs between the two
  platforms is either a genuine platform difference worth documenting or a bug
  in the Windows-specific branch; say which one you think it is and why.

## Reporting

Same shape as the Linux skill: severity order, what the user would see, file
and line, the command and output that shows it, and the smallest fix you can
describe. Call out explicitly which parts of the Windows surface you did not
exercise - GUI apps in ConPTY, drive letters other than `C:`, non-English
locales and OpenSSH versions older than 9.x are all untested here.

## Cleanup

Shut the VM down cleanly when finished:

```bash
printf 'system_powerdown\n' | socat - UNIX-CONNECT:$HOME/vm/win2025/monitor.sock
```

or, if `socat` is unavailable and a hard stop is acceptable:

```bash
python3 - <<'PY'
import socket, os
s = socket.socket(socket.AF_UNIX)
s.connect(os.path.expanduser('~/vm/win2025/monitor.sock'))
s.sendall(b'quit\n')
PY
```

`quit` is a power cut - fine for a test box, but never use it if the user
asked you to leave the VM in a known-good state after installing something.
