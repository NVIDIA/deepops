# NVSentinel GPU health monitoring

[NVSentinel](https://github.com/NVIDIA/NVSentinel) watches the GPUs and kernel
messages on every GPU node of a Kubernetes cluster, turns what it finds into node
conditions, labels and events, and can optionally act on serious faults: stop a
node from receiving new work, move work off it, or reset or reboot it. It is part
and is documented upstream in the
[NVSentinel docs](https://github.com/NVIDIA/NVSentinel/tree/main/docs).

DeepOps installs it by default on Kubernetes clusters that use the GPU Operator.
The default setting watches every GPU node and **cordons** a node (stops new pods
being scheduled on it) when it reports a fatal GPU fault. Running pods are never
touched and nothing is rebooted unless you ask for that.

- [What DeepOps turns on by default](#what-deepops-turns-on-by-default)
- [The four steps](#the-four-steps)
- [Seeing it work](#seeing-it-work)
- [When a node is cordoned](#when-a-node-is-cordoned)
- [Keeping a node out of it](#keeping-a-node-out-of-it)
- [Small clusters and the circuit breaker](#small-clusters-and-the-circuit-breaker)
- [What DeepOps installs for it](#what-deepops-installs-for-it)
- [Security notes](#security-notes)
- [Footprint](#footprint)
- [Upgrading](#upgrading)
- [Slurm](#slurm)
- [Troubleshooting](#troubleshooting)
- [Settings reference](#settings-reference)

## What DeepOps turns on by default

| Setting | Default | Meaning |
|---|---|---|
| `nvsentinel_enabled` | `true` | Install NVSentinel after the GPU Operator in `playbooks/k8s-cluster.yml`. Skipped when `deepops_gpu_operator_enabled` is false. |
| `nvsentinel_mode` | `cordon` | Watch, and cordon a node on a fatal GPU fault. |

Two rules adjust the default for you:

- **One GPU node:** DeepOps uses `observe` instead of `cordon`. With a single GPU
  node, cordoning it leaves new work nowhere else to run. The playbook prints that
  it stepped down. Set `nvsentinel_mode_force: true` if you want `cordon` on a lab
  with one GPU node anyway.
- **Counting GPU nodes:** DeepOps counts the nodes that carry the label
  `nvidia.com/gpu.present=true`, as set by the GPU Operator. It does not use the
  inventory group, because that group can include CPU-only workers. If the
  GPU Operator has not labelled any node yet, the role stops with a message rather
  than guessing. Set `nvsentinel_gpu_node_count` to override the count.

Set the values in `config/group_vars/k8s_cluster.yml`, then apply them. The role
is safe to re-run; it always applies the complete settings for the chosen step.
The first time on an existing cluster, run the GPU Operator step with it, so the
DCGM service is switched on before NVSentinel starts:

```bash
ansible-playbook -l k8s_cluster playbooks/k8s-cluster.yml --tags nvidia-gpu-operator,nvsentinel
```

Later changes only need `--tags nvsentinel`. Add `--check` to see what would be
applied without changing the cluster. A full `playbooks/k8s-cluster.yml` run also
installs it.

To turn it off, set `nvsentinel_enabled: false` and run the same command. The
Helm release is removed. The database volume and secrets, cert-manager, the
`local-path` storage class and any labels already on nodes are left in place. The
GPU Operator's DCGM service follows `nvsentinel_enabled`; set
`gpu_operator_enable_dcgm: true` if you want to keep the DCGM service without
NVSentinel.

## The four steps

One setting, `nvsentinel_mode`, picks how far NVSentinel is allowed to go.

| Step | What runs | What happens to a node with a fault | Needs the database |
|---|---|---|---|
| `observe` | GPU health monitor, kernel-message (syslog) monitor, labeler, metadata collector, platform connector | Nothing. Conditions, labels and events appear on the node. | No |
| **`cordon`** (default) | + fault quarantine | The node is cordoned (and tainted) on a fatal fault, and uncordoned when a healthy event follows. Running pods keep running. | Yes |
| `drain` | + node drainer | Pods are also moved off the cordoned node. DeepOps policy for user namespaces is `AllowCompletion`: wait for jobs to finish, never force-kill them. System namespaces are excluded as upstream does. | Yes |
| `remediate` | + fault remediation, janitor | The GPU is reset or the node is rebooted through a privileged Job. | Yes |

Rules that apply to every step:

- **Dry run.** `nvsentinel_dry_run: true` sets NVSentinel's global dry-run switch:
  modules log what they would do and change nothing. DeepOps documents and uses
  only this global switch. The janitor has no dry-run, so DeepOps refuses
  `remediate` while dry-run is on.
- **`remediate` needs a second, explicit yes.** Set
  `nvsentinel_allow_node_reboot: true` as well, or the role stops with a message.
  It is never the default.
- **Stepping down works.** Every run applies the full settings for the chosen step
  and does not reuse earlier values, so going from `drain` back to `cordon`
  switches the drainer off. Changes made with `helm upgrade --set` by hand are
  replaced on the next run; change the DeepOps variables instead.

## Seeing it work

```bash
# Pods (all should be Running)
kubectl -n nvsentinel get pods

# Health conditions on a node (False = healthy)
kubectl get node <node> -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}' | grep -E '^(Gpu|SysLog)'

# Labels NVSentinel sets, including its state label when a node is quarantined
kubectl get nodes -L dgxc.nvidia.com/nvsentinel-state

# Events for a node
kubectl describe node <node>

# Circuit breaker state (cordon and higher): CLOSED is normal, TRIPPED needs a person
kubectl -n nvsentinel get cm circuit-breaker -o jsonpath='{.data.status}'; echo
```

A healthy idle node shows every `Gpu*` and `SysLog*` condition as `False` and
stays schedulable.

## When a node is cordoned

A cordoned node shows `SchedulingDisabled` in `kubectl get nodes`, has a
`dgxc.nvidia.com/nvsentinel-state=quarantined` label, and carries labels such as
`k8saas.nvidia.com/cordon-reason`. Pods already running on it keep running.

1. **Find the fault.** List the conditions that are `True` and read the node's
   events:

   ```bash
   kubectl get node <node> -o jsonpath='{range .status.conditions[?(@.status=="True")]}{.type}{"\n"}{end}'
   kubectl describe node <node>
   ```

2. **Fix the cause** (for example reseat or replace hardware, reset the GPU, or
   reboot during a maintenance window). When the fault clears and NVSentinel sees
   a healthy event, it uncordons the node itself.
3. **Uncordon by hand** only when no `Gpu*` or `SysLog*` condition is still `True`:

   ```bash
   kubectl uncordon <node>
   ```

   NVSentinel treats a manual uncordon as "stop the workflow for this node".
4. **If the circuit breaker tripped** (see below), NVSentinel stops acting on all
   events, healthy ones included, until a person resets it. After you have looked
   at the cordoned nodes and uncordoned the healthy ones:

   ```bash
   kubectl -n nvsentinel patch cm circuit-breaker -p '{"data":{"status":"CLOSED","cursor":"CREATE"}}'
   kubectl -n nvsentinel rollout restart deploy fault-quarantine
   kubectl -n nvsentinel rollout status deploy fault-quarantine
   ```

   `cursor: CREATE` discards events that piled up while the breaker was tripped so
   they cannot trip it again at once; use `RESUME` instead to process them.
   Resetting the breaker does not uncordon anything. Watch the cluster for 15 to
   30 minutes afterwards. The upstream
   [circuit breaker runbook](https://github.com/NVIDIA/NVSentinel/blob/v1.27.0/docs/runbooks/circuit-breaker.md)
   has the full procedure.

## Keeping a node out of it

Add `nvsentinel_unmanaged: true` to the host in `config/inventory` (or its
`host_vars`) and re-run the playbook. DeepOps labels the node
`nvsentinel.dgxc.nvidia.com/managed=false`. NVSentinel still stores that node's
events, but nothing acts on them. This is also a good way to keep NVSentinel from
cordoning a node during planned maintenance.

If a host's Kubernetes node name differs from its inventory name, set
`kube_override_hostname` on the host so DeepOps can match them; the role stops if
it cannot map the host to a live node.

The role adds the label but does not remove it. To bring a node back, remove the
variable and the label:

```bash
kubectl label node <node> nvsentinel.dgxc.nvidia.com/managed-
```

## Small clusters and the circuit breaker

From `cordon` upward the circuit breaker is always on. It stops NVSentinel from
cordoning more than a set share of your GPU nodes within a time window, and, once
tripped, it needs a person to reset it. DeepOps picks the threshold from the
number of GPU nodes:

| GPU nodes | Behavior |
|---|---|
| 1 | `observe` (see above) |
| 2 to 9 | Trips only if **every** GPU node would be cordoned (`percentage: 100`) |
| 10 or more | Upstream default: 50 % within 5 minutes |

Override with `nvsentinel_breaker_percentage` (1 to 100) and
`nvsentinel_breaker_duration` (default `5m`). If you add GPU nodes later, re-run
the playbook so the count is refreshed, or set `nvsentinel_gpu_node_count`.

## What DeepOps installs for it

| Needed | What DeepOps does |
|---|---|
| GPU Operator DCGM service (port 5555) | `gpu_operator_enable_dcgm` now follows `nvsentinel_enabled`, so the service is on by default. dcgm-exporter then uses this standalone DCGM service, which is the GPU Operator's normal mode. On an existing cluster the next GPU Operator run adds it. |
| Host-installed drivers | The labeler setting follows `gpu_operator_preinstalled_nvidia_software` (default `true`). Override with `nvsentinel_assume_driver_installed`. |
| Kubernetes 1.34 or newer | Checked by the role. |
| cert-manager 1.21 or newer (from `cordon` up) | Installed (chart v1.21.1, namespace `cert-manager`) if it is missing. If cert-manager or its CRDs already exist and are older than 1.21, or the version cannot be read, the role stops. DeepOps never upgrades an existing cert-manager. Upgrade it yourself, or use `observe`. |
| A storage class for the database (from `cordon` up) | Kubespray's `local_path_provisioner` is enabled (set in `config.example`) with `local_path_provisioner_is_default_storageclass: "false"`, so your cluster's default class is unchanged. The database uses `nvsentinel_storage_class` (default `local-path`) explicitly. To use your own class, set the variable to its name. The role stops if the class does not exist. |
| A database (from `cordon` up) | The [Percona Server for MongoDB operator](https://docs.percona.com/percona-operator-for-mongodb/) with **one** member (`nvsentinel_db_members: 1`). Use `3` on clusters with three or more schedulable nodes. Credentials are generated inside the cluster and are not written to logs. |
| Prometheus PodMonitor | Enabled only if the PodMonitor CRD exists (`nvsentinel_pod_monitor: true` to allow it). |

While the database is down, monitors keep writing node conditions, but cordon and
uncordon pause. Set `nvsentinel_priority_class` to give NVSentinel and its database
a priority class on busy clusters.

## Security notes

NVSentinel needs host access to read GPU and kernel state. Review this before you
use it on a shared or regulated cluster.

- **metadata-collector** (a DaemonSet on every GPU node) runs **privileged**, as
  root, with `hostPID` and `hostNetwork`. It reads GPU and NVSwitch topology
  through NVML, writes `/var/lib/nvsentinel` on the host, mounts the host's `/sys`
  and the kubelet pod-resources directory, and records which GPU each pod uses as
  a pod annotation.
- **syslog-health-monitor** (a DaemonSet on every GPU node) runs **as root** with
  the capabilities `CAP_SYS_ADMIN` and `CAP_SYSLOG`. It mounts the host's `/proc`,
  `/sys` and `/var/log` (which holds the journal) **read-only**, reads
  `/var/lib/nvsentinel` read-only, and keeps state in two directories under
  `/var/run`.
- **gpu-health-monitor** runs as root with the host network so it can reach the
  DCGM service. In the DeepOps setup it is not privileged.
- **platform-connectors** runs as root with all capabilities dropped.
- **janitor never touches control-plane nodes.** DeepOps always renders the janitor
  exclusion for `node-role.kubernetes.io/control-plane` at every step, so a
  combined control-plane and GPU node is never reset or rebooted, even in
  `remediate`. You can add exclusions with `nvsentinel_janitor_extra_exclusions`
  (a list of Kubernetes label selectors); the built-in one cannot be removed
  without editing the role.
- **Percona telemetry is off.** DeepOps sets `psmdb-operator.disableTelemetry: true`
  and keeps the database's automatic upgrades disabled (`upgradeOptions.apply:
  disabled`).
- **Third-party components.** cert-manager and the Percona operator are new on a
  cluster that did not have them. NVSentinel releases often and warns that APIs
  may change; DeepOps pins one chart version (see [Upgrading](#upgrading)).

### Images for air-gapped sites

Mirror these images (chart v1.27.0). The set grows with the step you choose.

| From | Images |
|---|---|
| Every step | `ghcr.io/nvidia/nvsentinel/{gpu-health-monitor (tags v1.27.0-dcgm-3.x and v1.27.0-dcgm-4.x),labeler,metadata-collector,platform-connectors,syslog-health-monitor}:v1.27.0` |
| `cordon` and up | `ghcr.io/nvidia/nvsentinel/fault-quarantine:v1.27.0` |
| | `percona/percona-server-mongodb:8.0.26-11`, `percona/percona-server-mongodb-operator:1.23.0`, `percona/fluentbit:5.0.9-1`, `percona/mongodb_exporter:0.40.0` |
| | `docker.io/lachlanevenson/k8s-kubectl:v1.25.4`, `ghcr.io/rtsp/docker-mongosh:2.5.2` (helper images) |
| | cert-manager v1.21.1 from `quay.io/jetstack`: `cert-manager-{controller,webhook,cainjector,startupapicheck}` |
| | the local-path provisioner images Kubespray deploys (provisioner v0.0.32) |
| `drain` and up | `ghcr.io/nvidia/nvsentinel/node-drainer:v1.27.0` |
| `remediate` | `ghcr.io/nvidia/nvsentinel/{fault-remediation,janitor,janitor-provider,gpu-reset}:v1.27.0` |

The chart itself is `oci://ghcr.io/nvidia/nvsentinel`. The rendered database spec
also names `percona/percona-backup-mongodb` and `percona/pmm-client`; both
features stay off in DeepOps. Chart repositories and image locations can be changed
with the `nvsentinel_chart` and `nvsentinel_cert_manager_*` variables.

## Footprint

Requests from the rendered chart (limits are higher):

| What | CPU | Memory |
|---|---|---|
| Per GPU node: GPU health monitor, syslog monitor, metadata collector, platform connector | about 0.5 | about 0.9 GiB |
| Cluster-wide, `observe`: labeler | 0.1 | 128 MiB |
| Cluster-wide, `cordon`: fault quarantine | 1 | 1 GiB |
| `drain`: node drainer | 0.2 | 300 MiB |
| `remediate`: fault remediation | 0.2 | 300 MiB |
| Database, one member | 1 | 1.5 GiB, plus an 8 GiB volume |

The Percona operator and the janitor set no requests. Actual use on idle GPU nodes
is much lower than the requests.

## Upgrading

DeepOps pins NVSentinel chart `v1.27.0` (`nvsentinel_chart_version`) and cert-manager
`v1.21.1` (`nvsentinel_cert_manager_chart_version`). The pins are re-checked once
per DeepOps release and not changed between releases. You can set another chart
version, but only the pinned one is tested with these settings. Re-running the
playbook applies the pinned version and your current settings.

## Slurm

NVSentinel covers Kubernetes only. Slurm clusters installed by DeepOps run on the
hosts directly and keep their existing health checks (NHC and the host DCGM role).

## Troubleshooting

**The GPU health monitor cannot reach DCGM.** Check that the GPU Operator's DCGM
service exists:

```bash
kubectl -n gpu-operator get svc nvidia-dcgm
kubectl -n gpu-operator get pods | grep dcgm
```

The service appears a minute or two after the GPU Operator run finishes. If you
set `gpu_operator_enable_dcgm: false`, the monitor has nothing to talk to.

**The database pod is `Pending`.** Its volume claim has no storage class to bind
to. Check `kubectl -n nvsentinel get pvc` and that the class named by
`nvsentinel_storage_class` exists (`kubectl get storageclass`).

**The database pod restarts and every other pod waits on it.** Percona Server for
MongoDB 8.0.26-11, the image in chart v1.27.0, refuses to start on Linux kernels
6.19 and newer (MongoDB issue SERVER-121912). Check the node kernel with
`uname -r`. Until a database image that supports your kernel is available, run
`nvsentinel_mode: observe` (no database) or use a kernel older than 6.19 on the
node that runs the database.

**`no matches for kind "PerconaServerMongoDB"` when moving from `observe` to a
higher step.** Helm installs a chart's CRDs only on first install, not on upgrade,
so an existing `observe` release has no database CRDs. Apply them once, then run
the playbook again:

```bash
helm show crds oci://ghcr.io/nvidia/nvsentinel --version v1.27.0 | kubectl apply --server-side -f -
```

**cert-manager is too old.** The role stops with the version it found. Upgrade
cert-manager to 1.21 or newer yourself, or use `observe`, which needs no
certificates.

**A node was cordoned and you want to know why.** See
[When a node is cordoned](#when-a-node-is-cordoned).

## Settings reference

Set in `config/group_vars/k8s_cluster.yml`. Defaults are in
`roles/nvsentinel/defaults/main.yml`.

| Variable | Default | Purpose |
|---|---|---|
| `nvsentinel_enabled` | `true` | Install (`true`) or remove (`false`) NVSentinel |
| `nvsentinel_mode` | `cordon` | `observe`, `cordon`, `drain` or `remediate` |
| `nvsentinel_mode_force` | `false` | Keep the requested step on a single GPU node |
| `nvsentinel_allow_node_reboot` | `false` | Required for `remediate` |
| `nvsentinel_dry_run` | `false` | Global dry-run (not allowed with `remediate`) |
| `nvsentinel_gpu_node_count` | discovered | Override the GPU node count |
| `nvsentinel_db_members` | `1` | Database members (`1` or `3`) |
| `nvsentinel_storage_class` | `local-path` | Storage class for the database |
| `nvsentinel_priority_class` | none | Priority class for NVSentinel and its database |
| `nvsentinel_breaker_percentage` | automatic | Circuit breaker threshold, 1 to 100 |
| `nvsentinel_breaker_duration` | `5m` | Circuit breaker window |
| `nvsentinel_janitor_extra_exclusions` | `[]` | Extra node selectors the janitor must skip |
| `nvsentinel_pod_monitor` | `true` | Create a PodMonitor if the CRD exists |
| `nvsentinel_assume_driver_installed` | follows `gpu_operator_preinstalled_nvidia_software` | Labeler driver setting |
| `nvsentinel_unmanaged` | `false` | Per host: keep this node out of NVSentinel |
| `nvsentinel_chart_version` | `v1.27.0` | Pinned chart version |
