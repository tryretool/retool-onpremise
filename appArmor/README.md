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

The Docker daemon auto-applies its built-in `docker-default` AppArmor profile to every container it starts, and that profile contains a blanket `deny mount,` rule. The bundled `gvisor-seccomp.json` profile already permits `mount` / `umount2` / `pivot_root` (those are explicitly allow-listed for gVisor + pasta), but AppArmor sits in front of seccomp and rejects the syscall first. The visible symptom is pasta exiting with `Failed to remount /: Permission denied`; runsc's mount calls would be the next failure if pasta were skipped.

`docker-default` is loaded into the kernel by the Docker daemon at startup; it usually isn't present as a file in `/etc/apparmor.d/`. We ship a replacement profile (`docker-default` in this directory) with the same name but with the `deny mount,` rule removed. Loading it with `apparmor_parser -r` replaces the in-kernel version, and new containers — including those spawned by the agent-sandbox-controller — pick up the permissive variant. The rest of upstream `docker-default`'s hardening (the `/proc`, `/sys`, sysrq, ptrace denylists) is kept intact.

To enable on the host:

1) Copy the provided `docker-default` profile to `/etc/apparmor.d/docker-default`.

2) Replace the loaded profile:

```
sudo apparmor_parser -r /etc/apparmor.d/docker-default
```

You do **not** need to restart Docker after this — already-running containers keep their existing profile, and any new container will use the replaced version.

Note: the Docker daemon re-loads its built-in `docker-default` every time it starts, so you'll need to re-run the `apparmor_parser -r` command after any `systemctl restart docker` (or reboot).

