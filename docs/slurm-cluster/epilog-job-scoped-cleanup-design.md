# Design note: job-scoped Slurm epilog cleanup (issue #1407)

Status: design only, no code. Awaiting compatibility sign-off before implementation.

## 1. What the epilog does today

`epilog.sh` runs every executable in `epilog.d/` through `shared/bin/run-parts.sh`.
The dispatcher decides two things with `squeue`:

- `exclusive`: the job held every CPU on its nodes. Gates `*-exclusive-*` scripts
  (GPU reset, CPU governor, drop caches). Not in scope here.
- `last_user_job`: the user has no other job on this node in states
  running, suspended, stopped, configuring or resizing. Gates `*-lastuserjob-*`.

The `*-lastuserjob-*` scripts are all **per user**, not per job:

| Script | Action | Scope today |
|---|---|---|
| `40-lastuserjob-processes` | `killall -9 -u $SLURM_JOB_USER` | every process the user owns on the node |
| `41-lastuserjob-ssh` | remove user from `/etc/localusers` | user's SSH allow entry |
| `42-lastuserjob-cleanup` | `find -user … \| rm -fr` under `/tmp`, `/dev/shm` | every file the user owns there |
| `50-lastuserjob-all-enroot-dirs` | `rm -rf` enroot runtime and data paths | the user's `user-$(id -u)` directories, shared by all their jobs on the node |

Accounts listed in `localusers.backup` and root are exempt. 26.09 (#1391, #1404)
made these scripts fail closed: a failed or empty `squeue`, an unresolvable user,
or an unreadable mount table skips the step instead of deleting on a partial view.

The only thing that makes this cleanup approximately job-scoped is the
`last_user_job` guard, and that guard is an inference from controller state:

1. **Race.** With the default `CompleteWait=0` the controller can place a new job
   for the same user on this node after `squeue` answers and before `killall` runs.
2. **Controller view, not node view.** `squeue` reports what the controller
   believes. It cannot see processes that escaped the job cgroup, and it lags
   the node during controller load or a brief RPC failure.
3. **No ownership signal on files.** Files carry a UID, never a job id. Two jobs
   of one user on one node share `/tmp`, `/dev/shm` and the enroot directories.

Slurm itself already kills everything inside the ending job's step cgroups
(`proctrack/cgroup`). The real value of script 40 is reaping processes that got
*out* of that cgroup (user systemd slices, lingering sessions, adopt failures).

## 2. Proposed job-scoped behaviour

Principle: decide with **node-local, job-owned evidence** (`SLURM_JOB_ID`,
`SLURM_JOB_UID`, the cgroup tree). When evidence is missing or unparsable, do
nothing and log; never fail the epilog, since a failing epilog drains the node.

**Dispatcher guard (`run-parts.sh`).** Keep the `squeue` check and add a local
check: scan the cgroup tree for any `job_<id>` other than the ending job that
contains a process owned by `SLURM_JOB_UID`. Either source saying "another job
is here" sets `last_user_job=0`. Support cgroup v1 (`/slurm/uid_N/job_M`) and
v2 (`…/slurmstepd.scope/job_M`); an unrecognised layout logs a warning and is
treated as "another job may be here" (fail closed).

**40, processes.** Replace `killall -9 -u` with an explicit PID list owned by
`SLURM_JOB_UID`, classified by `/proc/PID/cgroup`:

| PID is in… | Action |
|---|---|
| the ending job's `job_$SLURM_JOB_ID` cgroup | kill (belt and braces behind Slurm) |
| any other `job_*` cgroup | never kill, regardless of what `squeue` said |
| no Slurm job cgroup (escaped/orphan) | kill only when `last_user_job=1` (today's useful behaviour) |
| an unparsable cgroup line | skip and log |

This closes the race in 1.1: a job the controller has not reported yet is still
visible by its cgroup.

**42, files.** Files have no job identity, so per-job deletion is not possible
from ownership alone. Proposal: keep per-user deletion but only behind the
strengthened guard above. Document the Slurm `job_container/tmpfs` plugin as the
genuine job-scoped answer for `/tmp` and `/dev/shm`; when it is active, 42 is
redundant for those paths and skips with a log line. Wiring `job_container.conf`
into the role is a separate follow-up, not part of this change.

**50, enroot.** Per-job enroot paths were considered and rejected: users rely on
containers persisting across jobs, and pyxis already offers `container_scope=job`
for job-lifetime containers. Keep per-user removal behind the strengthened guard.

**41, SSH.** Already per user by nature and backed by `pam_slurm_adopt` plus
`slurm_restrict_node_access`. Keep behind the guard. Its `grep -w` / unanchored
`sed` match is a small correctness fix that can ride along; it is not a scope change.

## 3. What changes for existing users

- **Less deletion, never more.** Every change narrows what is reaped. Nothing
  previously spared becomes a target.
- **Deferred cleanup.** When the local scan finds a same-user job that `squeue`
  missed, files and enroot directories persist until that job's epilog. This is
  a delay, not a loss.
- **cgroup v2 nodes.** If v2 is not supported in the first cut, fail-closed means
  `*-lastuserjob-*` never runs there and `/tmp` fills. v2 support is therefore a
  ship requirement, not a nice-to-have.
- **Site-added `*-lastuserjob-*` scripts** inherit the stricter guard and run
  less often. Release notes must say so.
- **`killall` to PID list.** Processes appearing between scan and kill are
  missed. Today's `killall` has the same window, so no regression; the window
  only exists for orphans, since other-job PIDs are spared by construction.
- **Exempt accounts and root** are unchanged.

## 4. Migration and opt-in flag

New role variable `slurm_epilog_cleanup_scope` with values `user` (today's
behaviour, byte-identical rendered scripts) and `job` (section 2). Rendering is
done at deploy time through the existing Jinja templates; no runtime switch.

Two schedules are possible; the choice is the owner's:

| | 26.11 | 27.01 |
|---|---|---|
| **A: opt-in first (recommended)** | ship flag, default `user`, deprecation note | default flips to `job`; `user` kept one more train |
| **B: default on** | ship flag, default `job` | remove `user` |

**Decision (owner, 2026-10-01): schedule B.** 26.11 ships the flag with default
`job`; `user` remains available as an escape hatch for one train and is removed
in 27.01. Because the default changes for every upgrading site, the 26.11
release notes must call this out, and the hardware fixture in section 5 is a
ship requirement for 26.11, not a follow-up.

Why B still carries risk even with testing: the fixture covers the layouts we
know about (cgroup v1 and v2, enroot, gang scheduling). A site with a custom
epilog, a non-cgroup process tracker, or user daemons that live outside any job
cgroup gets different behaviour on upgrade. The `user` value exists so such a
site can restore 26.09 behaviour with one variable while reporting the gap.

## 5. Test plan

**Unit, no root, no Slurm.** Extend `tests/slurm-epilog/run-tests.sh`, which already
renders the templates and drives them with a stub `squeue`. Add overridable roots
for the cgroup tree and `/proc` so fixtures can supply fake layouts.

1. Guard: `squeue` says last job, local scan shows another `job_*` for the UID
   (v1 and v2 layouts) → lastuserjob scripts skipped. Unrecognised layout →
   skipped and logged. Both sources clear → scripts run.
2. Script 40: one PID per row of the table in section 2, with a stub `kill`
   recording its arguments. Exempt user and root → no kill calls.
3. Script 42: `job_container` mount detected → skip with log. Existing mount
   boundary and owner-resolution tests still pass unchanged.
4. Script 50: skipped when another job for the UID is present; runs when last.
5. Snapshot: `scope=user` renders byte-identical to the 26.09 scripts.
6. `render.py` gains the new variable; `StrictUndefined` catches any template
   that forgets it.

**Overlapping-jobs fixture, real Slurm on disposable nodes** (built by the test
owner, separate approval for hardware runs):

1. Jobs A and B, same user, same node. A ends while B runs → B's processes,
   `/tmp` and `/dev/shm` files and enroot container survive.
2. Same, with B suspended under gang scheduling.
3. B is allocated during A's epilog (`CompleteWait=0`) → B unaffected.
4. User's last job ends → orphan process, `/tmp` files and enroot dirs are
   removed (regression of the useful behaviour).
5. Exempt operator with a login shell on the node → untouched.
6. Controller unreachable during the epilog → nothing deleted, node not drained.
7. Repeat 1 and 4 on a cgroup v2 node.

**Gates before "ready":** role lint, playbook syntax check, `run-tests.sh`
green, molecule unaffected (slurm role is already excluded).

## 6. Decisions (owner, 2026-10-01)

1. Schedule B (section 4): default `job` in 26.11, `user` removed in 27.01.
2. cgroup v2 support is required in the first cut; unrecognised layouts
   fail closed (skip and log).
3. `job_container/tmpfs` is documented only; role wiring is a separate issue.
4. The script 41 match fix rides along in the same change.

Implementation is not started by this note. It begins as a separate task once
the test owner has the overlapping-jobs fixture scheduled.
