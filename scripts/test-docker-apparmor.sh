#!/usr/bin/env bash
# Checks that setup-docker-apparmor.sh loads our docker-default profile and that
# it is still loaded after Docker restarts. It removes the profile, restarts
# Docker twice and installs the profile again, so only run it on a throwaway
# host (CI or a test VM).
#
# Usage: sudo scripts/test-docker-apparmor.sh --yes

set -euo pipefail

if [ "${1:-}" != "--yes" ]; then
  echo "This restarts Docker. Run it on a throwaway host with: sudo $0 --yes" >&2
  exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "Run this as root." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE=alpine:3.20

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Docker's stock docker-default has `deny mount,` and ours allows mount.
try_mount() {
  docker run --rm --cap-add SYS_ADMIN "$IMAGE" mount -t tmpfs none /mnt 2>&1
}

# docker.service allows 3 starts a minute, which a fresh Docker install plus this script can exceed.
restart_docker() {
  systemctl reset-failed docker
  systemctl restart docker
}

[ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" = "Y" ] || fail "AppArmor isn't enabled on this host"
echo "Docker $(docker version --format '{{.Server.Version}}')"
docker pull -q "$IMAGE" >/dev/null

# Start from Docker's stock profile, so the checks below only pass if ours gets loaded.
rm -f /etc/systemd/system/docker.service.d/retool-apparmor.conf /etc/apparmor.d/docker-default
systemctl daemon-reload
echo -n docker-default > /sys/kernel/security/apparmor/.remove 2>/dev/null || true
restart_docker
if out=$(try_mount); then
  fail "a container could mount before setup, so Docker's stock profile isn't being enforced"
fi
case "$out" in
  *"ermission denied"*) echo "OK: Docker's stock profile blocks mount" ;;
  *) fail "expected a permission error before setup, got: $out" ;;
esac

"$SCRIPT_DIR/setup-docker-apparmor.sh"
out=$(try_mount) || fail "a container can't mount after setup: $out"
echo "OK: our profile is loaded after setup"
"$SCRIPT_DIR/setup-docker-apparmor.sh" --check || fail "--check still wants changes right after setup"

restart_docker
out=$(try_mount) || fail "our profile was replaced when Docker restarted: $out"
echo "PASS: our profile is still loaded after a Docker restart"
