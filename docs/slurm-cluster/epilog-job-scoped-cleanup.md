# Job-scoped epilog cleanup

Starting with release 26.11, the Slurm epilog cleans up after a finished job
without touching other jobs of the same user that are running on the same node.
This page explains what changed, why, and how to go back to the old behaviour
for one release.

## What changed

When a job ends, the epilog (`/etc/slurm/epilog.d/*-lastuserjob-*`) removes what
the user left behind on the node: stray processes, files in `/tmp` and
`/dev/shm`, enroot containers, and the user's SSH access entry.

Before 26.11 this was decided from the controller's view alone: the epilog asked
`squeue` whether the user had another job on the node, and if not it killed
every process the user owned (`killall -9 -u`) and deleted everything they owned
in `/tmp` and `/dev/shm`. Two things could go wrong:

- A new job of the same user could be placed on the node just after `squeue`
  answered, and have its processes killed a moment later.
- The controller can lag behind the node, and it cannot see processes that left
  the job's cgroup.

With `slurm_epilog_cleanup_scope: job` (the new default) the epilog also looks
at the node itself. Every process of a Slurm job lives in a `job_<id>` cgroup, so
the epilog reads `/proc/<pid>/cgroup` (cgroup v1 and v2 are both understood) and
decides per process:

| Process is in… | Epilog does |
|---|---|
| the ending job's cgroup | kills it (Slurm does too; this is a backstop) |
| another job's cgroup | never touches it, whatever `squeue` said |
| no job cgroup (an orphan, for example a leftover daemon) | kills it only when the user has no other job on the node |
| a cgroup entry it cannot read or recognise | leaves it alone and logs it |

The file cleanup (`/tmp`, `/dev/shm`), enroot directory removal, and SSH access
removal still happen per user, because files carry a user id and not a job id.
They now run only when neither `squeue` nor the node's cgroups show another job
of that user. If that check cannot be completed, the cleanup is skipped and
logged, then happens when the user's next job ends. A skipped cleanup is a delay,
not a loss.

In short: **less is deleted, never more.** Nothing that was spared before is
removed now.

### What you may notice

- If a user's job is still running when another of their jobs ends, that job's
  processes, `/tmp` files and enroot containers now survive. Previously they
  could be removed.
- After the user's last job ends, leftovers are still removed as before.
- `/tmp` cleanup can be delayed on a node where the cgroup data cannot be read.
  The epilog logs a `[WARN]` line (`slurm` tag in the journal, also in
  `/var/log/slurm/prolog-epilog`) when it defers.
- Any extra `*-lastuserjob-*` script you added under `/etc/slurm/epilog.d`
  follows the same, stricter guard and therefore runs less often.
- Accounts listed in `/etc/slurm/localusers.backup`, and root, are exempt as
  before.
- Requires cgroup-based process tracking (`ProctrackType=proctrack/cgroup`, the
  DeepOps default). With a different process tracker the epilog cannot find job
  cgroups and will defer cleanup; use `user` (below) or fix the tracker.

### Related fix: SSH access entry

The script that removes a user's SSH access entry (`41-lastuserjob-ssh`) matched
names as patterns rather than whole lines: ending a job for user `al` could also
remove the entries for `alice` or `halley`, and a dot in a name matched any
character. It now matches the exact line. This applies in both scopes.

## Going back to the 26.09 behaviour

If you need the old behaviour, set this in `config/group_vars/slurm-cluster.yml`
and re-run the Slurm playbook (`ansible-playbook playbooks/slurm-cluster.yml`) so the epilog scripts are re-rendered on the compute nodes:

```yaml
slurm_epilog_cleanup_scope: user
```

The scripts for `user` are the 26.09 scripts byte-for-byte (apart from the SSH
match fix above). The playbook prints a deprecation notice when `user` is set.

**`user` is deprecated and will be removed in release 27.01.** It exists for one
release so a site with an unusual setup, for example a custom epilog, a process
tracker other than cgroup, or user daemons that live outside any job cgroup, can
keep the old behaviour while it reports the gap. If you need `user`, please open
an issue at https://github.com/NVIDIA/deepops/issues saying why.

## Per-job `/tmp` and `/dev/shm`: `job_container/tmpfs`

The complete answer for per-job temporary files is Slurm's own
`job_container/tmpfs` plugin, which gives each job a private `/tmp` and
`/dev/shm` that disappear when the job ends. DeepOps does not configure it for
you, but if you enable it in `slurm.conf` the epilog notices
(`JobContainerType=job_container/tmpfs`) and skips its own `/tmp` and `/dev/shm`
file cleanup, since the plugin already handles it:

```
JobContainerType=job_container/tmpfs
```

and add a `job_container.conf` next to `slurm.conf`. See the Slurm documentation
for `job_container.conf` (the `BasePath` must exist and be writable by slurmd on
each compute node). Wiring this into the role is tracked separately.

## Enroot and Pyxis

The enroot cleanup removes the user's runtime and data directories, which are
shared by all of that user's jobs on the node. Per-job enroot directories were
considered and not adopted, because people rely on containers persisting between
jobs. If you want containers that disappear with the job, Pyxis has a
container scope setting for job-lifetime containers; see the Pyxis documentation
for your version.

## Checking what the epilog did

Each epilog logs through `logger -t slurm-epilog` and `-t slurm`. Typical lines:

```
slurm-epilog: Job-scoped process cleanup for alice job 4711: killed 3, spared 12, unclassified 0
slurm: Another job of alice has processes on this node (found by cgroup); not running the last-user-job scripts.
```

## Testing

The unprivileged unit tests are in `tests/slurm-epilog/run-tests.sh` and run in CI.
They use a fake `/proc` and cover both cgroup layouts.
