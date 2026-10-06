# Overlapping Slurm jobs: installed-epilog fixture

**Destructive integration test for an exclusively leased disposable cluster.**
The offline commands below are safe without Slurm or root. The live procedure is
not authorized merely by this README or by a successful offline test. Obtain an
explicit approval naming the target, installation/configuration changes, account
creation, job execution, possible cleanup/drain impact, lease window and recovery
first. The test owner verifies the lease and code provenance before execution.
`--approval` and `--lease` record references; they do not verify or grant authority.
Do not run on a shared workstation, production node, or shared controller.

This fixture changes files **under tests only** in the source repository. It runs
the installed epilog, not a copied/rendered substitute. Product epilog, dispatcher
and cleanup scripts remain unchanged. Installation of the test wrapper and any
Slurm configuration change are separate, explicitly approved operator actions.
No host firewall rule, controller shutdown or delayed background injector is used.

## Offline validation

From the repository root:

```bash
python3 tests/slurm-epilog/overlapping-jobs/test_fixture.py
bash tests/slurm-epilog/overlapping-jobs/run-fixture.sh --selftest
bash tests/slurm-epilog/run-tests.sh
for f in tests/slurm-epilog/overlapping-jobs/*.sh \
         tests/slurm-epilog/overlapping-jobs/jobs/*.sh \
         tests/slurm-epilog/overlapping-jobs/hooks/*; do bash -n "$f"; done
```

The Python suite exercises actual helper calls, CLI parsing, the actual EXIT trap,
failed queries, missing assertions/epilog END, enroot import/create/start failures,
ID-only cancellation, refusal of existing accounts/hooks and cgroup-v2 repetition.
Host dependencies are replaced, and job-test asset roots are relocated to an
isolated temporary directory. It never invokes live preflight or changes hosts.
Set `PAPERCLIP_SCRATCH_DIR` or `TMPDIR` when temporary files must live in a specific
scratch directory. These tests are **not** hardware certification.

## Required live environment

- Root on one disposable host running controller, compute and login functions;
  node name must equal `hostname -s`. No running **or pending** jobs, outside
  submissions, reservations used by others, or concurrent fixture runs.
- Bash, Python 3 (JSON report), coreutils, procps, util-linux (`runuser`, `setsid`,
  `unshare`), journalctl, Slurm commands and working enroot. Passwordless local
  root operations; never supply a password through this fixture. Enroot must be
  installed before setup; a minimal Slurm installation may omit it (for example,
  with `slurm_install_enroot=false`). Install it through the approved provisioning
  procedure, or enable `slurm_install_enroot` when provisioning the test host.
- Installed DeepOps epilog at `/etc/slurm/epilog.sh`, dispatcher at
  `/etc/slurm/shared/bin/run-parts.sh`, hooks at `/etc/slurm/epilog.d`, a regular
  `/etc/slurm/localusers.backup`, and working journal logging of epilog START/END.
  Save the installed commit/render inputs separately; the fixture saves hashes,
  copies, Slurm config, job states and logs for the actual installation.
- `/etc/slurm` must be root-owned; `/etc/slurm/epilog.d` must be owned by
  `root:slurm` or stricter (for example, `root:root`). Neither directory may be
  group/world writable; mode `0755` is sufficient. The driver's `trusted_path`
  check requires root ownership, no group/world write bits and no symlinks on
  checked paths and all ancestors, including `/etc/slurm/localusers.backup`.
  The DeepOps Slurm installation can leave these directories owned by `slurm`;
  correct ownership and permissions through the approved disposable-host setup
  procedure before running the driver. Do not weaken the trust check.
- `ProctrackType=proctrack/cgroup`, the appropriate task/cgroup configuration, a
  normal partition able to run two one-CPU jobs, and `CompleteWait=0` for S3.
  No job-container/private-tmp setting hiding fixture files from the host;
  assertions fail closed if assets cannot be seen.
- Enroot image contains Bash and sleep. An approved, pinned site image is preferred
  to the default `docker://ubuntu:24.04`. Import, create, an acknowledgement from
  **inside** the container and its live named process must all succeed. The enroot
  data/runtime settings must match those rendered into the installed epilog;
  otherwise the last-user directory-removal assertion will fail legitimately.
  Resolved data/runtime roots must be absent before the first job and distinct,
  non-overlapping paths for the two new users. Existing state for a reused numeric
  UID is refused rather than handed to the product's per-user cleanup.
- For S2, `PreemptMode` includes `GANG`, and a dedicated partition on the same node
  has `OverSubscribe=FORCE:2` (or more). Use at least two CPUs. A requests one CPU;
  B and a different-user scheduling peer request N−1 CPUs each. This keeps real
  gang contention after A ends. The fixture never issues `scontrol suspend`.
  It must observe A RUNNING and B SUSPENDED before A ends, and B still SUSPENDED
  after the epilog. Tune `SchedulerTimeSlice` to give the epilog time to finish;
  if the state changes in that window the result is INCONCLUSIVE, not a pass.
  A/B/peer startup has a 360-second bound. Save partition and scheduler settings.
- S7 requires an actual cgroup-v2 filesystem and reruns S1 and S4 using fresh tags;
  `--scenarios 7` executes both, it does not skip them. For full layout coverage,
  run S1–S6 on a cgroup-v1 installation and S7 on a separately approved cgroup-v2
  installation, or run the full default suite on v2 as an additional matrix leg.
  A subset MATCH is not evidence for unrequested scenarios or another layout.
- Set Slurm `EpilogTimeout` above the fixture's three-minute hold/injection bounds
  (allow at least five minutes); account for site RPC timeouts. An expiration or
  missing END is a test failure/inconclusive result, never permission to proceed.

Provision/configure these prerequisites through the site's approved test procedure
**before** invoking the driver. It does not silently reconfigure Slurm or resume a
drained node. A failed query, unknown layout, missing dependency or stale resource
stops setup. `--no-enroot`, `--keep-users`, empty/duplicate/invalid scenario lists,
unsafe account/path values and manual suspension mode are rejected.

## Install the fixture after approval

Run as root from the reviewed source checkout on the approved disposable target.
All fixture files and ancestors must be root-owned, not group/world writable and
not symlinks. Do not execute root code from a user-writable worktree.

```bash
F=/opt/deepops-epilog-fixture
SRC=tests/slurm-epilog/overlapping-jobs
test ! -e "$F" && test ! -L "$F" || exit 2
install -d -m 0755 "$F" "$F/jobs" "$F/hooks"
install -m 0755 "$SRC/run-fixture.sh" "$SRC/epilog-wrapper.sh" "$F/"
install -m 0755 "$SRC/jobs/fixture-job.sh" "$SRC/jobs/login-shell.sh" "$F/jobs/"
install -m 0755 "$SRC/hooks/00-fixture-probe" "$SRC/hooks/10-fixture-hold" "$F/hooks/"
install -m 0644 "$SRC/README.md" "$F/"
```

### S6 wrapper: explicit configuration change

Before installing, save the existing `slurm.conf` and its Epilog setting to an
operator-owned recovery directory. Refuse an existing wrapper path. Install:

```bash
test ! -e /etc/slurm/epilog-fixture-wrapper && \
  test ! -L /etc/slurm/epilog-fixture-wrapper || exit 2
install -m 0755 "$F/epilog-wrapper.sh" /etc/slurm/epilog-fixture-wrapper
```

In the **approved disposable installation only**, set:

```ini
Epilog=/etc/slurm/epilog-fixture-wrapper
```

Apply the configuration by the site's approved Slurm reconfiguration procedure;
confirm `scontrol show config` reports that exact path. The driver requires a
byte-for-byte match with the reviewed wrapper. The wrapper ordinarily `exec`s
`/etc/slurm/epilog.sh`. For the single marked S6 job only, it invokes the same
installed script in a fresh, disconnected network namespace. The driver and
slurmd retain their original namespace and controller connectivity. The wrapper
records both namespace identities, invocation-specific stderr and exit status.
A synchronous `timeout --kill-after=5 180` bounds the child; no worker can add a
rule after teardown. Isolation/timeout failure records an inconclusive test and
returns zero to Slurm to avoid an injector-induced drain. The fixture still
requires the product epilog END, its failed-squeue warning, asset survival and
normal node state; injector failure cannot match.

## Run commands and assertions

Example commands after prerequisites, approval and lease validation:

```bash
# Supply actual authorization/lease references and partition names.
F=/opt/deepops-epilog-fixture
bash "$F/run-fixture.sh" --expect current --scenarios 1,2,3,4,5,6 \
  --node "$(hostname -s)" --partition "$TEST_PARTITION" \
  --gang-partition "$GANG_PARTITION" --approval "$APPROVAL_REF" \
  --lease "$LEASE_REF" --out /root/epilog-baseline-v1

# Separately approved cgroup-v2 target; output path must not already exist.
bash "$F/run-fixture.sh" --expect current --scenarios 7 \
  --node "$(hostname -s)" --partition "$TEST_PARTITION" \
  --approval "$APPROVAL_REF" --lease "$LEASE_REF" --out /root/epilog-baseline-v2

# After installing the independently approved job-scoped candidate on v2:
bash "$F/run-fixture.sh" --expect job-scoped --scenarios 1,2,3,4,5,6,7 \
  --node "$(hostname -s)" --partition "$TEST_PARTITION" \
  --gang-partition "$GANG_PARTITION" --approval "$APPROVAL_REF" \
  --lease "$LEASE_REF" --out /root/epilog-candidate-v2
```

Use an external test window of at most 90 minutes per matrix leg, with at least
15 minutes of lease remaining for rollback. Operator supervision is required.
TERM requests cleanup; if an external timeout is used, allow at least ten minutes
before KILL so cancellation and epilog completion can finish. Never immediately
rerun over stale state. The account names default to distinct random run-scoped
names. Explicit `--user`/`--operator` values must be new, distinct accounts (root
and every pre-existing UID, including UID-zero aliases, are refused).

| Scenario | Required evidence and behavior |
|---|---|
| 1 | A END, pre-existing B process/files/enroot process+directory and an outside-job orphan; all survive while B runs; no drain |
| 2 | S1 plus actual GANG/FORCE configuration, scheduler-created SUSPENDED B, A RUNNING and suspended-state evidence across A's epilog |
| 3 | CompleteWait=0; A held after the dispatcher's squeue decision; B RUNNING with all assets while A remains COMPLETING and hold has not timed out; release A, await END, inspect B |
| 4 | Verified pre-existing outside-job orphan, A scratch and enroot directory; after last-job END all removed; no drain. A's in-job process death alone does not count |
| 5 | Real Bash login shell (`shopt login_shell`) outside a job cgroup, with verified PID/executable and pre-existing scratch; exempt operator's shell/scratch survive its job END |
| 6 | Epilog alone in a different network namespace; failed-squeue warning from that invocation; END and successful wrapper completion; pre-existing orphan/scratch/enroot directory unchanged; controller still queryable and node not drained |
| 7 | Fresh S1 and S4 repetitions on verified cgroup v2, with separate evidence/report; both must match |

### Reviewed baseline acceptance disposition

Technical review (2026-10-02) resolved the original request for “S1 FAIL on
26.09” as a mistaken reproduction assumption, not a scope or risk change.
No owner acceptance decision remains for this interpretation. Baseline `26.09`
(`facc47e4`) already protects same-user RUNNING and SUSPENDED jobs through
#1391/#1404. Retain all seven numbered scenarios above with these roles:

- **S1/S2:** survival controls on both baseline and candidate. A live S1/S2
  failure is a baseline regression: stop and report; do not treat it as the
  intended race reproduction.
- **S3:** race reproduction on baseline (B's assets removed after the dispatcher
  decision), survival on the job-scoped candidate. If the baseline does not
  remove B's assets, the race was not reproduced: stop and report, not pass.
- **S4:** useful last-job cleanup must still remove the verified outside-job
  orphan, scratch and enroot directory on both baseline and candidate.
- **S5–S7:** unchanged; retain the operator exemption, failed-query safety and
  cgroup-v2 repetitions with their existing evidence requirements.

A baseline MATCH is not candidate sign-off. Hardware remains unrun; these are
source-derived expectations and offline evidence, not a live reproduction or
hardware certification. Explicit approval naming the target, lease/window,
installation/configuration changes, account creation, job execution, cleanup/drain
impact and recovery remains mandatory before any live run. This disposition
changes no product code, fixture behavior, expectation values, coverage, safety
gates or exit semantics.

<details>
<summary>Superseded historical evidence — original discrepancy wording</summary>

The following wording is preserved unchanged as historical evidence. Its pending
decision requirement is superseded by the reviewed disposition above.

#### Baseline acceptance discrepancy — decision still required

At tag `26.09` (`facc47e456659049b62802c0a3145e593b9af6ff`), the
installed-source dispatcher already excludes last-user cleanup when another
same-user RUNNING **or SUSPENDED** job exists. Its offline dispatcher tests verify
both cases. Therefore S1 and S2 are expected to preserve B on that baseline.
The race in S3 is different: B arrives **after** the dispatcher's decision, and
`--expect current` expects its assets to be removed. Under `--expect job-scoped`
S3 expects survival. These are source-derived expectations, not a claim that a
live reproduction has been observed.

An acceptance request for “S1 FAIL on 26.09” conflicts with those semantics.
Do not force S1 to fail, relabel S3 as S1, or use a baseline MATCH as candidate
sign-off. The test owner must route the scenario-number decision to the owner
before live baseline sign-off. Keep all seven scenarios in the ship-gate record.

</details>

## Reports, exit codes and cleanup

`report.md`, `report.tsv` and (with Python 3) `report.json` retain every assertion,
per-scenario verdict and notes. S7 has its own nested report. A requested scenario
needs its complete mandatory assertion set; an empty set or skipped enroot check
cannot MATCH. Logs go to stderr and `driver.log`, never into job-ID/path output.

- `0`: every requested scenario matched the selected expectation model.
- `1`: behavioral mismatch (may be the desired improvement when using baseline
  expectations against newer code; review the individual checks).
- `2`: invalid arguments, setup/execution/cleanup error.
- `3`: missing evidence, incomplete assertions or failed preconditions.
- `130` / `143`: INT / TERM preserved through cleanup and report generation.

The driver first creates the exclusive `/run/deepops-epilog-fixture` lock, then
root-owned `/var/lib/epilog-fixture-<run-id>/ctl`. Jobs cannot create release,
hold, fault or hook-ledger controls. Per-account writable status directories are
separate. `ownership.txt` records exact identities and state paths. `ctl/jobs`
records only IDs returned by this run's sbatch; cancellation never uses `-u`.
Hook ownership is persisted, including calls made in command substitutions.
Homes are explicitly created at `BASE/home-ACCOUNT`, never adopted from the
system's default home-directory location. Completed IDs are retired from the
active ledger after successful cleanup and retained in `jobs.tsv` for evidence;
the fixture will not keep cancelling aged-out IDs in subsequent scenarios.
Each job/asset has a run-and-scenario-specific tag. No cross-run wildcard deletion
is performed. Existing accounts, output paths, lock/state and hook paths are
refused rather than adopted or overwritten.

Normal teardown releases parked jobs/holds, cancels only recorded IDs, verifies
job termination, removes owned hooks, removes exact owned scratch/container names,
restores `localusers.backup`, removes the recorded new enroot data/runtime roots
(with ownership checks and filesystem-boundary protection), deletes the two new
accounts/private groups and run state, and
releases the lock. Cleanup failure retains state and returns nonzero. Finalization
never cancels jobs or removes node resources before successful ownership setup.
The wrapper is operator-installed and **is not removed by the driver**.

For interrupted execution, SIGKILL, power loss or cleanup failure:

1. Retain the output, `ownership.txt`, root control directory and both ledgers.
   Never guess ownership from a username or delete `epilog-fixture-*` globally.
2. Using the exact recorded job IDs/tags, release corresponding `release-job-TAG`
   and `release-epilog-ID` markers in that control directory, cancel those IDs,
   and verify they have finished. Hold hooks self-release after three minutes;
   jobs/login shells have a 30-minute watchdog. Namespace injection has no host
   network state to restore, and its child is synchronously timeout-bounded.
3. Remove only hook paths from `ctl/hooks` after epilogs finish. Restore the saved
   `ctl/localusers.backup` if present; compare with current state before overwriting
   any unexpected administrator change. Reap only the recorded newly created
   accounts' processes, remove their exact tagged assets/containers and the
   initially absent enroot roots recorded in `ownership.txt`, then delete those
   accounts and their private groups. Do not reuse the supplied names for another run.
4. Remove the exact run directory, `control-path` and empty lock only after proving
   no job/epilog still uses them. If ownership or controller state is uncertain,
   stop and recover/reprovision the disposable target rather than broad cleanup.
5. Restore the original Slurm Epilog setting/configuration through the approved
   reconfiguration procedure. Verify no fixture jobs remain and the normal epilog
   path is active, then remove `/etc/slurm/epilog-fixture-wrapper` and the exact
   fixture installation. Review any drain reason; never blindly resume a node.
6. Preserve all evidence and verify the leased target is clean or reprovisioned
   before releasing it. Site-wide image caches may have been populated by enroot
   import/prolog; shared caches are deliberately not recursively deleted. Include
   any site-specific cache cleanup in the approved recovery plan, or reprovision. No release/tag/publication is implied by this test.
