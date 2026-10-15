# Live tests

These run against a real `sshd` instead of fakes. They are skipped by a plain
`flutter test` - each file checks an environment variable and skips the whole
group when it is missing, so they cost nothing in the normal suite.

The target is a container, which is the cheapest thing that behaves like a
machine you can also switch off:

```bash
podman build -t termphin-testvm test/live          # Containerfile below
podman run -d --name termphin-vm -p 127.0.0.1:34022:22 termphin-testvm
```

Then:

```bash
# SFTP, shell, forwarding, remote agent install
TERMPHIN_LIVE_SSH_PORT=34022 flutter test test/live/live_ssh_test.dart

# Disconnects, frozen hosts, power cuts - needs the container name
TERMPHIN_LIVE_SSH_PORT=34022 TERMPHIN_LIVE_CONTAINER=termphin-vm \
  flutter test test/live/live_resilience_test.dart --concurrency=1

# Concurrency, big trees, transfer integrity
TERMPHIN_LIVE_SSH_PORT=34022 flutter test test/live/live_stress_test.dart

# Nagle vs TCP_NODELAY, measured both ways
TERMPHIN_LIVE_SSH_PORT=34022 flutter test test/live/live_latency_test.dart

# A dropped session resumed in place
TERMPHIN_LIVE_SSH_PORT=34022 TERMPHIN_LIVE_CONTAINER=termphin-vm \
  flutter test test/live/live_resume_test.dart --concurrency=1

# Huge files, device nodes, failing local writes
TERMPHIN_LIVE_SSH_PORT=34022 flutter test test/live/live_limits_test.dart
```

`--concurrency=1` matters for the resilience file: it kills and restarts the
container, so no other suite may be talking to it at the same time.

`live_resilience_test.dart` needs the agent binaries in `assets/` to be
current: it installs whatever is bundled, then kills the machine under it. Run
`scripts/update_agent_from_github.sh [tag]` first if the agent has had a
release since.

`offline_edges_test.dart` needs nothing and runs in the normal suite.

## Containerfile

```dockerfile
FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server sudo ca-certificates coreutils procps \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /run/sshd \
    && useradd -m -s /bin/bash tester \
    && echo 'tester:testpass' | chpasswd \
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && echo 'AllowTcpForwarding yes' >> /etc/ssh/sshd_config \
    && echo 'GatewayPorts yes' >> /etc/ssh/sshd_config
EXPOSE 22
CMD ["/usr/sbin/sshd","-D","-e"]
```
