## AppArmor

Ubuntu 24.04 and onwards [Ubuntu restricts the creation of unprivilaged user namespaces](https://ubuntu.com/blog/ubuntu-23-10-restricted-unprivileged-user-namespaces) by default via [AppArmor](https://documentation.ubuntu.com/server/how-to/security/apparmor/).
Creation of unrestricted user namespaces is fundemental to the sandboxing tool, [nsjail](https://github.com/google/nsjail), that Code Executor uses to execute user code in isolation. As such we have provided an AppArmor profile that selectively gives the required permissions to the nsjail binary that is run in Code Executor.

To enable the profile on host machine:

1) Install AppArmor profiles:

```
sudo apt install apparmor-profiles
```

2) Copy the provided `usr.bin.nsjail` AppArmor profile to `/etc/apparmor.d/usr.bin.nsjail`


3) Load the profile:

```
sudo apparmor_parser /etc/apparmor.d/usr.bin.nsjail
```

## Agent Sandbox: replacing `docker-default`

The agent-sandbox-controller spawns sandbox containers over the Docker socket. Inside each sandbox, two mount-using tools run:

- [pasta](https://passt.top/) sets up isolated networking and remounts `/` to make the root mount private.
- [runsc (gVisor)](https://gvisor.dev/) in `--rootless` mode mounts `proc`, `tmpfs`, `/dev`, and calls `pivot_root` to assemble its second-level sandbox — even when networking is disabled.

The Docker daemon auto-applies its built-in `docker-default` AppArmor profile to every container it starts. The bundled `gvisor-seccomp.json` profile already permits `mount` / `umount2` / `pivot_root` (those are explicitly allow-listed for gVisor + pasta), but AppArmor sits in front of seccomp and rejects the syscall first. The visible symptom is pasta exiting with `Failed to remount /: Permission denied`; runsc's mount calls would be the next failure if pasta were skipped.

`docker-default` is loaded into the kernel by the Docker daemon at startup; it usually isn't present as a file in `/etc/apparmor.d/`. We ship a replacement profile (`docker-default` in this directory) with the same name. Loading it with `apparmor_parser -r` replaces the in-kernel version, and new containers — including those spawned by the agent-sandbox-controller — pick up our variant. The rest of upstream `docker-default`'s hardening (the `/proc`, `/sys`, sysrq, ptrace denylists) is kept intact.

### What's different from upstream `docker-default`

Three deltas:

1. **Replaced `deny mount,` with `mount,`.** Upstream blocks all mount operations at the AppArmor layer. Agent-sandbox needs `mount` for pasta (remount `/` private) and runsc (mount `proc` / `tmpfs` / `/dev`). A bare `mount,` rule is a broad allow.
2. **Added `pivot_root,`.** `pivot_root` is a distinct AppArmor mediation class from `mount` and is also default-deny once any other mount-class rule exists in the profile. pasta and runsc both call `pivot_root` to swap rootfs into their sandboxes, so we need an explicit allow. Symptom without it: `apparmor="DENIED" operation="pivotroot" ...` for `comm="passt.avx2"` and `comm="exe"` (runsc) on `/tmp/` and `/proc/fs/`.
3. **Explicit `signal` rules.** Upstream historically didn't include any `signal` rules. AppArmor 4.x (Ubuntu 24.04+) treats a profile that has *any* rules but no `signal` rules as default-deny for cross-profile signals, which surfaces as `apparmor="DENIED" operation="signal" ... comm="runc"` audit lines during container teardown. We add explicit rules for peer=docker-default and receive-from-unconfined to match the implicit behavior on older kernels.

All `/proc`, `/sys`, sysrq, kcore, powercap, security and ptrace deny rules are kept verbatim from upstream so the rest of the hardening surface is unchanged.

### Why an explicit `mount,` rule is needed (and not just dropping the `deny`)

`#include <abstractions/base>` brings in narrow mount rules on Ubuntu 24.04+ (e.g. specific tmpfs / proc allowances). That puts the profile into "default-deny for unmatched mounts" mode — once any mount rule exists in the evaluated profile, every other mount must match an allow rule. Removing `deny mount,` alone leaves only the abstraction's narrow allows, so pasta's `mount / / -o rw,rslave` falls through to a default-deny and the audit log shows `info="failed mntpnt match"`. The broad `mount,` rule explicitly permits unmatched mount syscalls.

### Installation

Run the bundled script:

```
sudo ./scripts/setup-docker-apparmor.sh
```

It is idempotent and skips cleanly on hosts without AppArmor (e.g. macOS Docker Desktop). What it does:

1. Copies the bundled `docker-default` profile to `/etc/apparmor.d/docker-default`.
2. Loads it into the kernel with `apparmor_parser -r` so new containers pick it up.
3. Installs a systemd drop-in at `/etc/systemd/system/docker.service.d/retool-apparmor.conf` containing `ExecStartPre=-/usr/sbin/apparmor_parser -r /etc/apparmor.d/docker-default`. This makes the docker daemon re-apply our profile on every start, so the override survives `systemctl restart docker` and host reboots without manual intervention.

`./install.sh` invokes this script automatically; only run it directly if you're applying the AppArmor change to an existing install or to a host where `install.sh` was run on an older version of this repo.

You do **not** need to restart Docker after a first-time install — already-running containers keep their existing profile, and any new container will use the replaced version.

### Verifying it's in effect

After loading, trigger a fresh sandbox spawn and tail the kernel audit log:

```
sudo dmesg -wT | grep -iE 'apparmor|audit'
```

You should see no `apparmor="DENIED"` lines for `operation="mount"` or `operation="signal"`. If you do, capture the line — it points at the next rule that needs widening.

This step only applies on Linux hosts where AppArmor is active. macOS hosts running Docker Desktop don't enforce AppArmor (the LinuxKit VM kernel ships without it), so no override is needed there; `apparmor_parser` won't be available on those machines.

