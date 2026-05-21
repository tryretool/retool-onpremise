#!/usr/bin/env bash
# Installs the Retool-customized docker-default AppArmor profile and a
# systemd drop-in that auto-reloads it on every docker.service start.
#
# Why this exists: the Docker daemon resets its built-in `docker-default`
# AppArmor profile every time it starts, so without the drop-in our overrides
# revert on any `systemctl restart docker` or host reboot. The drop-in calls
# apparmor_parser -r on each docker start so the right profile is always live.
#
# Assumes system Docker (docker.service). Rootless Docker uses a different
# unit and would need a different drop-in path.
#
# Modes:
#   (no args)  install / reconcile state; loud, idempotent
#   --check    report state and exit. 0 = no changes needed (or skip case),
#              1 = persistent changes would be made. Reads only; no sudo
#              required, no mutations. Intended for install.sh gating.

set -euo pipefail

CHECK_ONLY=0
case "${1:-}" in
  --check) CHECK_ONLY=1 ;;
  "") ;;
  *) echo "Usage: $0 [--check]" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_PROFILE="$REPO_ROOT/appArmor/docker-default"
DST_PROFILE="/etc/apparmor.d/docker-default"
DROPIN_DIR="/etc/systemd/system/docker.service.d"
DROPIN_FILE="$DROPIN_DIR/retool-apparmor.conf"

# --- Preflight (same in both modes) -------------------------------------

if ! command -v apparmor_parser >/dev/null 2>&1; then
  [ "$CHECK_ONLY" = "1" ] || echo "  ℹ️  apparmor_parser not found — host doesn't use AppArmor. Skipping."
  exit 0
fi

if [ ! -d /sys/kernel/security/apparmor ]; then
  [ "$CHECK_ONLY" = "1" ] || echo "  ℹ️  AppArmor not active in this kernel. Skipping."
  exit 0
fi

if [ ! -f "$SRC_PROFILE" ]; then
  echo "  ❌ Bundled profile not found at: $SRC_PROFILE" >&2
  exit 2
fi

# --- Compute desired state ---------------------------------------------

read -r -d '' DESIRED_DROPIN_CONTENT <<EOF || true
[Service]
# Auto-installed by retool-onpremise scripts/setup-docker-apparmor.sh.
# Re-loads the Retool-customized docker-default AppArmor profile on every
# Docker daemon start. The daemon resets the in-kernel docker-default at
# startup, so without this, our override reverts after every restart.
# Leading '-' makes systemd ignore failure (e.g. profile file missing) so
# docker can still start.
ExecStartPre=-/usr/sbin/apparmor_parser -r ${DST_PROFILE}
EOF

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

profile_matches=0
if [ -f "$DST_PROFILE" ] && cmp -s "$SRC_PROFILE" "$DST_PROFILE"; then
  profile_matches=1
fi

dropin_matches=0
if [ -d /run/systemd/system ] && [ -f "$DROPIN_FILE" ]; then
  # The drop-in might be readable without sudo; try without first.
  current="$(cat "$DROPIN_FILE" 2>/dev/null || $SUDO cat "$DROPIN_FILE" 2>/dev/null || true)"
  if [ "$current" = "$DESIRED_DROPIN_CONTENT" ]; then
    dropin_matches=1
  fi
fi

# --- --check: report and exit ------------------------------------------

if [ "$CHECK_ONLY" = "1" ]; then
  if [ "$profile_matches" = "1" ] && { [ ! -d /run/systemd/system ] || [ "$dropin_matches" = "1" ]; }; then
    # Persistent state already correct. (Kernel state can't be cheaply
    # verified from here, but a present-matching drop-in guarantees the next
    # docker start will load our profile — that's the meaningful invariant.)
    exit 0
  fi
  exit 1
fi

# --- Install the profile file ------------------------------------------

if [ "$profile_matches" = "1" ]; then
  echo "  ✅ docker-default profile at $DST_PROFILE already matches bundled copy."
else
  echo "  📝 Installing docker-default profile to $DST_PROFILE..."
  $SUDO cp "$SRC_PROFILE" "$DST_PROFILE"
fi

# --- Load it into the kernel now ---------------------------------------

# apparmor_parser -r is idempotent for the same content; replaces the
# in-kernel docker-default with ours. Already-running containers keep their
# previously-loaded profile; any new container picks up the replacement.
echo "  🔄 Loading docker-default profile into the kernel..."
$SUDO apparmor_parser -r "$DST_PROFILE"

# --- Install systemd drop-in for persistence ---------------------------

if [ ! -d /run/systemd/system ]; then
  echo "  ℹ️  Not running under systemd — skipping persistent drop-in install."
  echo "  ⚠️  Re-run this script after any docker daemon restart or host reboot."
  exit 0
fi

if [ "$dropin_matches" = "1" ]; then
  echo "  ✅ systemd drop-in at $DROPIN_FILE already up to date."
else
  echo "  📝 Writing systemd drop-in to $DROPIN_FILE..."
  $SUDO mkdir -p "$DROPIN_DIR"
  printf '%s\n' "$DESIRED_DROPIN_CONTENT" | $SUDO tee "$DROPIN_FILE" >/dev/null
  echo "  🔄 Reloading systemd..."
  $SUDO systemctl daemon-reload
fi

echo
echo "  ✅ docker-default AppArmor profile is installed and persistent."
echo
echo "  Verify after the next sandbox container spawns:"
echo "    sudo dmesg -wT | grep -iE 'apparmor|audit'"
echo "  You should see NO 'apparmor=\"DENIED\"' entries for"
echo "  operation=mount / pivotroot / signal."
