#!/usr/bin/env python3
"""Runs Termphin's Maestro E2E suite and verifies server-side SSH artifacts."""

import argparse
import os
import subprocess
import sys
import time

RAW_CAPTURE_PL = r"""#!/usr/bin/perl
use strict;
use warnings;
my $out = $ARGV[0] || '/tmp/e2e_raw.hex';
system('stty raw -echo');
open(my $fh, '>', $out) or die $!;
my $buf = '';
my $ch;
while (sysread(STDIN, $ch, 1) == 1) {
    $buf .= $ch;
    if (substr($buf, -6) eq '~DONE~') {
        $buf = substr($buf, 0, length($buf) - 6);
        last;
    }
}
print $fh join(' ', map { sprintf('%02x', ord($_)) } split(//, $buf)), "\n";
close($fh);
system('stty sane');
"""

EXPECTED_RAW_SEGMENTS: list[tuple[str, bytes]] = [
    ("1. Typing + Backspace x3 + next char", b"abXYZ\x7f\x7f\x7fc"),
    ("2. Backspace + CTRL oneshot + plain char", b"\x7f\x03c"),
    ("3. CTRL locked (a, e) + unlock (a)", b"\x01\x05a"),
    ("4. ALT oneshot (b, b) + ALT locked (f, b) + unlock (f)", b"\x1bbb\x1bf\x1bbf"),
    (
        "5. Page 1 keys (ESC, HOME, END, TAB, arrows)",
        b"\x1b\x1b[H\x1b[F\x09\x1b[D\x1b[A\x1b[B\x1b[C",
    ),
    (
        "6. Page 2 keys (S+TAB, DEL, BKSP, PAGE_UP, PAGE_DN, F1-F3)",
        b"\x1b[Z\x1b[3~\x7f\x1b[5~\x1b[6~\x1bOP\x1bOQ\x1bOR",
    ),
    ("7. SHIFT oneshot (a -> A, then a)", b"Aa"),
    (
        "8. SHIFT locked (b->B, 1->!, SHIFT+PgUp, SHIFT+Tab, SHIFT+Up, SHIFT+Right) + unlock (c)",
        b"B!\x1b[5;2~\x1b[Z\x1b[1;2A\x1b[1;2Cc",
    ),
]


def ssh_exec(
    runtime: str, container: str, cmd: str, stdin_text: str | None = None
) -> subprocess.CompletedProcess[str]:
    if runtime in ("podman", "docker"):
        full_cmd = [runtime, "exec", "-i", container, "sh", "-c", cmd]
    else:
        full_cmd = ["sh", "-c", cmd]
    return subprocess.run(
        full_cmd,
        input=stdin_text,
        capture_output=True,
        text=True,
    )


def verify_raw_hex(hex_text: str) -> bool:
    tokens = hex_text.strip().split()
    actual = bytes(int(t, 16) for t in tokens if t)
    expected = b"".join(seg for _, seg in EXPECTED_RAW_SEGMENTS)
    if actual == expected:
        print(f"  PASS raw byte capture: exact match ({len(actual)} bytes)", flush=True)
        for name, seg in EXPECTED_RAW_SEGMENTS:
            print(f"    OK {name}: {seg.hex(' ')}", flush=True)
        return True

    print(
        f"  FAIL raw byte capture: expected {len(expected)} bytes, got {len(actual)} bytes",
        flush=True,
    )
    offset = 0
    for name, seg in EXPECTED_RAW_SEGMENTS:
        got = actual[offset : offset + len(seg)]
        mark = "OK  " if got == seg else "DIFF"
        print(f"    {mark} {name}", flush=True)
        if got != seg:
            print(f"         expected: {seg.hex(' ')}", flush=True)
            print(f"         actual:   {got.hex(' ')}", flush=True)
        offset += len(seg)
    if len(actual) > offset:
        print(f"    EXTRA trailing bytes: {actual[offset:].hex(' ')}", flush=True)
    return False


def verify_file(runtime: str, container: str, path: str, expected: str) -> bool:
    res = ssh_exec(runtime, container, f"cat {path}")
    if res.returncode != 0:
        print(f"  FAIL {path}: missing ({res.stderr.strip()})", flush=True)
        return False
    got = res.stdout.strip()
    if got != expected:
        print(f"  FAIL {path}: expected {expected!r}, got {got!r}", flush=True)
        return False
    print(f"  PASS {path} == {expected!r}", flush=True)
    return True


def run_flow(flow_path: str, env_vars: dict[str, str], timeout_s: int = 600) -> int:
    env = os.environ.copy()
    env["PATH"] = env.get("PATH", "") + ":" + os.path.expanduser("~/.maestro/bin")
    env["MAESTRO_CLI_NO_ANALYTICS"] = "1"
    env["TERM"] = "dumb"
    cmd = ["maestro", "test", "--no-ansi"]
    for k, v in env_vars.items():
        cmd.extend(["-e", f"{k}={v}"])
    cmd.append(flow_path)
    print(f"\n=== Running {flow_path} ===", flush=True)
    try:
        proc = subprocess.run(cmd, env=env, timeout=timeout_s)
        return proc.returncode
    except subprocess.TimeoutExpired:
        print(f"TIMEOUT {flow_path} after {timeout_s}s", flush=True)
        return 124


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-id", default="dev.termphin.termphin.debug")
    parser.add_argument("--ssh-host", default="10.0.2.2")
    parser.add_argument("--ssh-port", default="34122")
    parser.add_argument("--ssh-user", default="tester")
    parser.add_argument("--ssh-pass", default="testpass")
    parser.add_argument(
        "--runtime",
        choices=("podman", "docker", "local"),
        default="podman",
        help="Where the test sshd runs: podman container, docker container, or local host.",
    )
    parser.add_argument(
        "--container",
        default="termphin-maestro-ssh",
        help="Container name when --runtime is podman or docker.",
    )
    parser.add_argument(
        "--home-dir",
        default="/home/tester",
        help="Home directory of the test SSH user (e.g. /home/tester or /Users/tester).",
    )
    parser.add_argument(
        "flows",
        nargs="*",
        default=[
            ".maestro/01_onboarding_and_auth.yaml",
            ".maestro/02_terminal_input_raw.yaml",
            ".maestro/03_sessions_and_dock.yaml",
            ".maestro/04_sftp_and_snippets.yaml",
            ".maestro/05_settings_and_security.yaml",
        ],
    )
    args = parser.parse_args()

    sftp_dir = f"{args.home_dir.rstrip('/')}/e2e_dir"

    # Install raw capture script and clean old artifacts on the SSH server.
    prep = ssh_exec(
        args.runtime,
        args.container,
        "cat > /tmp/raw_capture.pl && chmod 755 /tmp/raw_capture.pl && "
        "rm -rf /tmp/e2e_raw.hex /tmp/e2e_bs.txt /tmp/e2e_ctrl.txt "
        f"/tmp/e2e_alive.txt /tmp/e2e_snip.txt {sftp_dir}",
        stdin_text=RAW_CAPTURE_PL,
    )
    if prep.returncode != 0:
        print(f"Failed to prepare SSH server: {prep.stderr}", flush=True)
        return 1

    env_vars = {
        "APP_ID": args.app_id,
        "SSH_HOST": args.ssh_host,
        "SSH_PORT": args.ssh_port,
        "SSH_USER": args.ssh_user,
        "SSH_PASS": args.ssh_pass,
    }

    all_ok = True
    for flow in args.flows:
        rc = run_flow(flow, env_vars)
        if rc != 0:
            print(f"FAIL {flow} (maestro exit {rc})", flush=True)
            all_ok = False
            continue
        time.sleep(1.5)
        base = os.path.basename(flow)
        if base == "02_terminal_input_raw.yaml":
            raw_res = ssh_exec(args.runtime, args.container, "cat /tmp/e2e_raw.hex")
            if raw_res.returncode != 0:
                print(f"  FAIL /tmp/e2e_raw.hex missing: {raw_res.stderr.strip()}", flush=True)
                all_ok = False
            elif not verify_raw_hex(raw_res.stdout):
                all_ok = False
            if not verify_file(args.runtime, args.container, "/tmp/e2e_bs.txt", "hi"):
                all_ok = False
            if not verify_file(args.runtime, args.container, "/tmp/e2e_ctrl.txt", "CTRL_OK"):
                all_ok = False
        elif base == "03_sessions_and_dock.yaml":
            if not verify_file(args.runtime, args.container, "/tmp/e2e_alive.txt", "ALIVE"):
                all_ok = False
        elif base == "04_sftp_and_snippets.yaml":
            dir_res = ssh_exec(args.runtime, args.container, f"test -d {sftp_dir} && echo OK")
            if dir_res.returncode == 0 and dir_res.stdout.strip() == "OK":
                print(f"  PASS {sftp_dir} created via SFTP", flush=True)
            else:
                print(f"  FAIL {sftp_dir} missing on server", flush=True)
                all_ok = False
            if not verify_file(args.runtime, args.container, "/tmp/e2e_snip.txt", "SNIP_OK"):
                all_ok = False

    print("\n=== SUITE RESULT:", "ALL PASSED ===" if all_ok else "FAILED ===", flush=True)
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
