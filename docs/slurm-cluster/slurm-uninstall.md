# Uninstalling Slurm

How to remove a DeepOps Slurm deployment from a node, including the single-node
(login-on-compute) layout.

- [Uninstalling Slurm](#uninstalling-slurm)
  - [Before you start](#before-you-start)
  - [What the Slurm playbook puts on a node](#what-the-slurm-playbook-puts-on-a-node)
  - [Uninstall procedure](#uninstall-procedure)
    - [1. Stop and disable the services](#1-stop-and-disable-the-services)
    - [2. Remove the Slurm build](#2-remove-the-slurm-build)
    - [3. Remove configuration, state, and logs](#3-remove-configuration-state-and-logs)
    - [4. Undo the login and PAM changes](#4-undo-the-login-and-pam-changes)
    - [5. Undo the system tweaks](#5-undo-the-system-tweaks)
    - [6. Controller only: database and accounting](#6-controller-only-database-and-accounting)
    - [7. Optional components](#7-optional-components)
    - [8. Reboot and verify](#8-reboot-and-verify)
  - [Reinstalling instead of uninstalling](#reinstalling-instead-of-uninstalling)

## Before you start

DeepOps installs Slurm from source and makes a number of system-level changes
on each node. There is no "undo" playbook: unlike the Kubernetes deployment,
which has the Kubespray reset playbook (see
[Reset the Cluster](../k8s-cluster/README.md#reset-the-cluster)), removing
Slurm is a manual procedure. The cleanest result on a node that is going to
be repurposed is always a fresh OS install. Use the steps below when that is
not an option.

Everything here assumes the default variable values from
`roles/slurm/defaults/main.yml`. If your `config/group_vars/slurm-cluster.yml`
overrides any of the variables named in the tables, substitute your values.

This is a destructive checklist, not a script to paste wholesale. Obtain a
maintenance window, drain jobs, and back up configuration, accounting, and
state before proceeding. Keep console access available. Check each path for
mounts, symlinks, custom prefixes, and use by other clusters or applications.
Never delete shared storage as part of removing only one node.

Run commands as root (or with `sudo`) on the node being cleaned.
On a single-node deployment the controller and compute steps both apply to
the same machine. Retain backups until a fresh login and the remaining
applications have been verified.

## What the Slurm playbook puts on a node

Systemd units (controller units exist only on `slurm-master` hosts, `slurmd`
only on `slurm-node` hosts):

| Unit | Where it comes from |
|---|---|
| `slurmctld.service`, `slurmdbd.service` | Copied from the Slurm build tree to `/etc/systemd/system/` |
| `slurmd.service` and the drop-in `/etc/systemd/system/slurmd.service.d/10-slurm-path.conf` | Same |
| `munge.service` | Distribution package `munge` |
| `mariadb.service` | Distribution package `mariadb-server` (controller only) |
| `docker.slurm-exporter.service`, `docker.node-exporter.service`, `docker.dcgm-exporter.service`, `docker.prometheus.service`, `docker.grafana.service`, `docker.alertmanager.service` | Only when `slurm_enable_monitoring` is set |

Files and directories (variable name in parentheses):

| Path | Purpose |
|---|---|
| `/usr/local/{bin,sbin,lib,include,share}` (`slurm_install_prefix`) | Slurm binaries, `libslurm*`, `lib/slurm/` plugins, man pages. Installed with `make install` into the shared `/usr/local` prefix |
| `/opt/deepops/build/slurm` (`slurm_build_dir`) | Slurm source and build tree. Kept after install unless `slurm_build_dir_cleanup` is set |
| `/opt/deepops/pmix`, `/opt/deepops/build/pmix` (`pmix_install_prefix`, `pmix_build_dir`) | PMIx built for Slurm |
| `/opt/deepops/hwloc`, `/opt/deepops/build/hwloc` (`hwloc_install_prefix`, `hwloc_build_dir`) | hwloc built for Slurm |
| `/etc/ld.so.conf.d/slurm.conf` | Adds the PMIx and hwloc library paths to the dynamic linker |
| `/etc/slurm` (`slurm_config_dir`) | `slurm.conf`, `cgroup.conf`, `gres.conf`, `slurmdbd.conf`, `prolog.d/`, `epilog.d/`, `shared/bin/`, `localusers.backup`, Pyxis `plugstack.conf.d/` |
| `/sw/.slurm` (`slurmctl_config_dir`) | Shared `slurm.conf` when `slurm_conf_symlink` is set |
| `/sw/slurm` (`slurm_ha_state_save_location`) | State directory when `slurm_enable_ha` is set |
| `/var/spool/slurm/ctld`, `/var/spool/slurm/d` | Controller and compute state |
| `/var/log/slurm` | Daemon logs |
| `/etc/sysconfig/slurmd` (`slurm_sysconf_dir`) | PMIx environment for `slurmd` |
| `/etc/rsyslog.d/99-slurm.conf` | Routes Slurm logs through rsyslog |
| `/etc/munge/munge.key` | Cluster-wide munge key |
| `/etc/localusers` | Users allowed to SSH without a job |
| `/local/slurm` (`slurm_user_home`) | Home of the `slurm` user (uid `slurm_user_uid`, default 22078) |
| `/lib/<multiarch>/security/pam_slurm_adopt.so` (`slurm_pam_lib_dir`; `/lib64/security` on RHEL) | PAM module built from the Slurm contribs |

System changes outside those paths:

- `/etc/pam.d/sshd` gets an `ANSIBLE MANAGED BLOCK (ansible-role-slurm)` that
  loads `pam_slurm_adopt`. With `slurm_restrict_node_access` (the default),
  SSH to a compute node is refused for users without a running job and not
  listed in `/etc/localusers`.
- `pam_systemd.so` is commented out in `/etc/pam.d/common-session` (Ubuntu)
  or `/etc/pam.d/password-auth` (RHEL).
- `/etc/default/grub` gets `cgroup_enable=memory swapaccount=1` appended to
  `GRUB_CMDLINE_LINUX` on compute nodes.
- `/etc/systemd/logind.conf` gets `RemoveIPC=no` on compute nodes.
- With `slurm_login_on_compute` (single-node layout) the SSH service unit gets
  a persistent `DeviceAllow=/dev/nvidiactl` property, stored under
  `/etc/systemd/system.control/<ssh unit>.d/50-DeviceAllow.conf`, so regular
  SSH sessions do not see the GPUs.
- The `slurm` system user and the MariaDB database `slurm_acct_db` plus the DB
  user `slurm` (controller).

## Uninstall procedure

Drain and stop all jobs first if the cluster is still in use. On a multi-node
cluster, clean the compute nodes before the controller so `slurmctld` does
not try to keep them registered.

### 1. Stop and disable the services

```bash
systemctl disable --now slurmd slurmctld slurmdbd 2>/dev/null
systemctl disable --now docker.slurm-exporter docker.node-exporter \
  docker.dcgm-exporter docker.prometheus docker.grafana docker.alertmanager 2>/dev/null
# Only if no other workload uses this authentication service:
# systemctl disable --now munge
```

### 2. Remove the Slurm build

**Complete [step 4](#4-undo-the-login-and-pam-changes) first**, while the PAM
module and configuration backups still exist. Verify a fresh SSH login before
removing any PAM module or Slurm configuration.

The build tree is kept by default, and its Makefile knows every file that
`make install` created. This is the most complete way to remove the binaries,
libraries, headers, and man pages from `/usr/local`:

```bash
cd /opt/deepops/build/slurm && make uninstall
cd /opt/deepops/build/slurm/contribs/pam_slurm_adopt && make uninstall
```

If the configured build tree is gone, recover the same Slurm version and
configure options to establish its installation manifest, or inventory files
manually. Typical entries include `srun`, `sinfo`, `sbatch`, `sacct`,
`slurmctld`, `slurmd`, `slurmdbd`, `slurmstepd`, `lib/slurm/`,
`include/slurm/`, Slurm man pages, and `pam_slurm_adopt.so` in
`slurm_pam_lib_dir`. Remove only files confirmed to belong to that installation.
Do not recursively delete `/usr/local` or glob `libpmi*` or man pages: those
can belong to other MPI stacks or applications.

Then, only if no other application uses these PMIx/hwloc installations,
remove the build trees and companion libraries (substitute custom paths):

```bash
rm -rf /opt/deepops/build/slurm /opt/deepops/build/pmix /opt/deepops/build/hwloc
rm -rf /opt/deepops/pmix /opt/deepops/hwloc
rm -f /etc/ld.so.conf.d/slurm.conf && ldconfig
```

Remove `/opt/deepops` entirely only if nothing else on the node uses it
(the NHC build, the DeepOps Python virtualenv, and other roles also install
under `/opt/deepops`).

### 3. Remove configuration, state, and logs

```bash
rm -f /etc/systemd/system/slurmctld.service /etc/systemd/system/slurmdbd.service \
      /etc/systemd/system/slurmd.service
rm -rf /etc/systemd/system/slurmd.service.d
systemctl daemon-reload

# Local paths only; inspect mounts/symlinks and save backups first.
rm -rf /etc/slurm
rm -rf /var/spool/slurm /var/log/slurm
rm -f /etc/sysconfig/slurmd
rm -f /etc/rsyslog.d/99-slurm.conf && systemctl restart rsyslog
```

`/sw/.slurm` (`slurmctl_config_dir`) and `/sw/slurm`
(`slurm_ha_state_save_location`) may be shared by the entire cluster. Preserve
them when removing one node. Remove them only once, after all controllers and
compute nodes are retired and a restorable backup has been made.

Stop and disable munge, then remove its package and key only if nothing else
needs it:

```bash
apt-get purge -y munge libmunge-dev   # Ubuntu
# dnf remove -y munge munge-devel munge-libs   # RHEL family
rm -rf /etc/munge
```

### 4. Undo the login and PAM changes

Do this from a console session or a second SSH session you keep open, and
test a fresh SSH login before closing it.

```bash
# Remove the pam_slurm_adopt block
sed -i '/# BEGIN ANSIBLE MANAGED BLOCK (ansible-role-slurm)/,/# END ANSIBLE MANAGED BLOCK (ansible-role-slurm)/d' /etc/pam.d/sshd

# Restore pam_systemd (Ubuntu)
sed -i 's/^# \(.*pam_systemd.so.*\) # ANSIBLE MANAGED (ansible-role-slurm)$/\1/' /etc/pam.d/common-session
# Restore pam_systemd (RHEL family)
# sed -i 's/^# \(.*pam_systemd.so.*\) # ANSIBLE MANAGED (ansible-role-slurm)$/\1/' /etc/pam.d/password-auth

# Inspect /etc/localusers for use by other PAM rules before removing it.
# /etc/slurm/localusers.backup is a DeepOps-generated list, not a pre-install backup.
# rm -f /etc/localusers
```

Single-node / `slurm_login_on_compute` layouts also hide the GPUs from SSH
sessions. Remove that property from the SSH unit (`ssh.service` on Ubuntu,
`sshd.service` on RHEL):

Inspect `systemctl cat ssh.service` (or `sshd.service`) and the file
`/etc/systemd/system.control/<ssh unit>.d/50-DeviceAllow.conf`. Back it up and
remove only the DeepOps `DeviceAllow=/dev/nvidiactl` setting; delete the file
only if it contains no other settings. Do **not** use `systemctl revert`,
which also removes unrelated local unit overrides. If the file has other
site-specific device rules, restore the site's intended policy instead.

Reload systemd and restart the SSH unit during the maintenance window, with
console access available. Check `systemctl show <ssh unit> -p DeviceAllow
-p DevicePolicy` and `nvidia-smi -L` from a new SSH session. If GPU access is
still restricted, inspect other device policy rather than clearing all
security restrictions.

### 5. Undo the system tweaks

Compute nodes only. Restore the pre-install values from backup; the commands
below illustrate the stock DeepOps additions, not a reason to replace a site's
existing IPC or kernel policy. On RHEL-family hosts, use the bootloader update
command appropriate for that OS and boot mode.

```bash
# Kernel command line (requires a reboot to take effect)
sed -i '/^GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX} cgroup_enable=memory swapaccount=1"$/d' /etc/default/grub
update-grub                                   # Ubuntu
# grub2-mkconfig -o /boot/grub2/grub.cfg      # RHEL family

# systemd-logind IPC cleanup
sed -i 's/^RemoveIPC=no$/#RemoveIPC=yes/' /etc/systemd/logind.conf
```

Remove the Slurm service account last, after the daemons are gone:

```bash
userdel -r slurm
```

### 6. Controller only: database and accounting

The controller keeps Slurm accounting in MariaDB. For a full cluster teardown
only, take and verify a database backup before dropping the configured database
and DB user. Do not do this when removing a compute node or one HA controller.
The following assumes the default names; retain MariaDB and its data directory
if any other application uses them:

```bash
mysql -e "DROP DATABASE IF EXISTS slurm_acct_db; DROP USER IF EXISTS 'slurm'@'localhost';"
# Optional: remove the server
# apt-get purge -y mariadb-server && rm -rf /var/lib/mysql   # Ubuntu
# dnf remove -y mariadb-server && rm -rf /var/lib/mysql      # RHEL family
```

### 7. Optional components

The Slurm cluster playbook also installs these when their flags are enabled.
Each is independent of Slurm and can stay in place if it is still useful.

| Component | Flag | What to remove |
|---|---|---|
| Enroot and Pyxis | `slurm_install_enroot`, `slurm_install_pyxis` (default on) | Pyxis configuration is under `/etc/slurm`; the configured plugin is `/usr/local/src/pyxis/spank_pyxis.so`, independent of `slurm_install_prefix`. Review the Pyxis build/install paths and Enroot package manifest. Remove Enroot only if no other workloads use it; see the AppArmor policy cleanup below. |
| Node Health Check | `slurm_install_nhc` | `/etc/nhc`, `/etc/sysconfig/nhc`, `/usr/sbin/nhc*`, `/usr/libexec/nhc`, `/opt/deepops/build/nhc` |
| OpenMPI | `slurm_cluster_install_openmpi` (example inventory: off; unset: on) | Built into `/usr/local` from `/tmp/openmpi-build`; `cd` to that directory and `make uninstall` if it still exists |
| Lmod / software modules | `slurm_install_lmod` | See `roles/lmod/defaults/main.yml` for `sm_software_path` and `sm_module_path`; profile scripts in `/etc/profile.d/` |
| Rootless Docker module | `playbooks/container/docker-rootless.yml` | See `roles/docker-rootless/defaults/main.yml` for `rootlessdocker_install_dir`; profile scripts in `/etc/profile.d/` |
| Monitoring | `slurm_enable_monitoring` | The listed monitoring units, including `docker.alertmanager.service` (stopped in step 1), their unit files in `/etc/systemd/system/`, and their matching containers. Inspect names and other users before removing containers; do not remove unrelated `docker.*` services. Run `systemctl daemon-reload` after removing unit files. Back up retained monitoring data; remove configuration and volumes only if no longer needed. |
| Centralized syslog | `slurm_enable_rsyslog_client` (default on) | `/etc/rsyslog.d/99-forward-syslog.conf` on compute nodes, then `systemctl restart rsyslog` |
| NFS | `slurm_enable_nfs_server`, `slurm_enable_nfs_client_nodes` | Exports and mounts configured by the NFS roles; see [Slurm and NFS](./slurm-nfs.md) |

When retiring Enroot, restore the site's intended AppArmor policy, not just
its files. For the scoped profile, unload `/etc/apparmor.d/enroot-nsenter`
through the distribution's tooling before removing the profile file, only if
no remaining workload needs it. If `pyxis_userns_allow_globally` was enabled,
inspect `/etc/sysctl.d/60-enroot-userns.conf`: it sets
`kernel.apparmor_restrict_unprivileged_userns=0` for the whole host. Back it up,
remove only the unneeded DeepOps override, and restore and apply the site's
intended value using the distribution's sysctl tooling. Check other sysctl
files for overrides and verify the effective value with
`sysctl kernel.apparmor_restrict_unprivileged_userns` where the knob exists.
Deleting the file alone does not restore the running kernel value. Review
remaining user-namespace workloads before tightening the policy.

The NVIDIA driver, CUDA toolkit, container toolkit, Docker, chrony, and the
`/etc/hosts` and hostname changes made by the generic playbooks are not Slurm
specific and are left in place by this procedure.

### 8. Reboot and verify

Reboot the node so the kernel command line and `logind` changes apply, then
check:

```bash
systemctl list-units --all 'slurm*' 'munge*'   # no running Slurm units; munge may be retained
command -v srun sinfo slurmd || echo "slurm binaries gone"
grep -c slurm /etc/pam.d/sshd                   # expect 0
nvidia-smi -L                                    # GPUs visible from a normal SSH session
```

## Reinstalling instead of uninstalling

If the goal is to rebuild Slurm binaries while keeping configuration, state,
and accounting, you do not need the removal procedure above. This is not a
clean-state reset. Set `slurm_force_rebuild: yes` in
`config/group_vars/slurm-cluster.yml` and rerun the playbook; the build step
runs `make uninstall` in the old build tree, removes the old plugin directory,
and rebuilds from source before reapplying the configuration.
