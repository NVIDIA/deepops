# Run:ai and KAI Scheduler (optional)

DeepOps can install open-source GPU scheduling on top of the GPU Operator. It is
**off by default** and changes nothing until you choose a mode.

| `runai_mode` | What you get | Status in 26.11 |
|---|---|---|
| `off` (default) | Nothing installed. | |
| `kai` | [KAI Scheduler](https://github.com/kai-scheduler/KAI-Scheduler): fair-share queues, gang scheduling, bin-packing, and pods that ask for a fraction of a GPU. | Supported. |
| `platform` | The Run:ai control plane and cluster: the above plus projects and quotas, a web UI, CLI and REST API. | **Experimental.** Included only if it passes a live check before the release freeze. |

The modes exclude each other. The Run:ai cluster chart ships its own KAI
Scheduler, so the role refuses to install one beside the other. Switch by
removing the first (`-e runai_state=absent`), then installing the second.

Not covered: multi-cluster setups, Knative/KServe/Training Operator add-ons,
and any DeepOps-owned UI. The web UI in `platform` mode is the upstream one.

## Requirements

- A DeepOps Kubernetes cluster with the GPU Operator (or the device plugin) and
  at least one node that advertises `nvidia.com/gpu`. The role refuses to run
  without one.
- Kubernetes 1.35 to 1.37 (the Kubespray default in this release is inside that range).
- `kai`: nothing else.
- `platform`, which you must provide before running the role:
  - a default StorageClass (`playbooks/k8s-cluster/nfs-client-provisioner.yml`)
  - a load balancer for a `LoadBalancer` service ([Load Balancer and Ingress](ingress.md)),
    or set `runai_platform_ingress_service_type: NodePort`
  - `kube-prometheus-stack` 88.6.5 or newer (`scripts/k8s/deploy_monitoring.sh`
    with `HELM_PROMETHEUS_CHART_VERSION` set)
  - a DNS name for the control plane, and a TLS certificate for it
  - room: the control plane alone wants about 10 CPU cores, 12 GB of memory and
    110 GB of disk; the cluster services about 10 cores, 20 GB, 50 GB. See the
    [Run:ai system requirements](https://docs.nvidia.com/run-ai/self-hosted/v3.0/documentation/installation-and-configuration/system-requirements.md)
    for production sizing; DeepOps only tests a single large node.

## Pinned versions

| Component | Version |
|---|---|
| KAI Scheduler chart | v0.18.5 (v0.18 is a long-term-support line) |
| gpu-fractioning (bundled in the KAI chart) | v0.1.7 |
| Run:ai control-plane and cluster charts | 3.0.20 |
| HAProxy ingress controller chart (platform) | 1.54.2 |

All are Apache-2.0. The Run:ai images come from `nvcr.io` without an NGC key.
Versions are variables (`runai_*_version`); pins are refreshed with each release.

## Install KAI Scheduler

1. Set the mode in `config/group_vars/k8s_cluster.yml`:

   ```yaml
   runai_mode: kai
   ```

2. Preview, then apply (runs on the first control-plane node):

   ```bash
   ansible-playbook -l kube_control_plane playbooks/k8s-cluster/runai.yml --check --diff
   ansible-playbook -l kube_control_plane playbooks/k8s-cluster/runai.yml
   ```

3. Check it:

   ```bash
   python3 scripts/validation/validate_runai.py --json
   ```

   The validator creates a temporary namespace and proves, with real pods, that
   (a) a pod using `schedulerName: kai-scheduler` in a queue ran `nvidia-smi`
   and completed, and (b) two pods that each asked for half a GPU landed on the
   same GPU and both completed. It requires `"ok": true`; if it is false, each
   entry in `failures` names the problem. The temporary namespace is deleted on
   success and kept on failure so you can look at it.

Rerunning the playbook is safe; a converged run reports `changed=0`.

### Submit a pod

Pods need three things: the scheduler name, a queue label, and (for a fraction) an
annotation. A fresh install creates `default-queue`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: half-gpu
  labels:
    kai.scheduler/queue: default-queue
  annotations:
    gpu-fraction: "0.5"
spec:
  schedulerName: kai-scheduler
  containers:
    - name: main
      image: nvcr.io/nvidia/cuda:13.0.2-base-ubuntu24.04
      command: ["nvidia-smi", "-L"]
```

Use a namespace of your own, not `kai-scheduler`. A pod cannot ask for both a
fraction and a whole GPU. Without `gpu-memory.*` settings (below), a fraction is
a scheduling promise, not a memory limit: nothing stops a pod from using more
GPU memory than its share.

To run the same vLLM quickstart pod through KAI instead of the default scheduler,
add `schedulerName: kai-scheduler` and the queue label to its pod spec. The default
scheduler stays the default.

### Optional: enforced GPU-memory limits

`runai_kai_gpu_fractioning: true` turns on the gpu-fractioning operator, which
caps each pod's GPU memory. It is opt-in because it needs a GPU stack the
DeepOps defaults do not use:

- GPU Operator **v26.7.1 or newer** (DeepOps pins v26.7.0 by default), and
- an NVIDIA driver **r615 or newer** on every GPU node. The GPU Operator does not
  choose r615 by default; set `gpu_operator_driver_version` to an r615 release
  and `gpu_operator_preinstalled_nvidia_software: false` (or install an r615 host
  driver yourself).

The role checks both and stops with an explanation if either is missing. It never
changes your driver or GPU Operator. Then verify the limits actually hold:

```bash
python3 scripts/validation/validate_runai.py --json --memory-enforcement
```

This also proves a pod inside its share completes and a pod that allocates past
its share is refused. In this mode pods ask for memory with the
`nvidia.com/container.<name>.gpu-memory.request` and `.limit` annotations; see the
[KAI GPU sharing guide](https://github.com/kai-scheduler/KAI-Scheduler/tree/v0.18.5/docs/gpu-sharing).

## Install the platform (experimental)

```yaml
runai_mode: platform
runai_platform_domain: "runai.example.com"
runai_platform_admin_user: "admin@example.com"
runai_platform_admin_password: "{{ vault_runai_admin_password }}"   # from an Ansible vault
```

```bash
ansible-playbook -l kube_control_plane playbooks/k8s-cluster/runai.yml
```

The role then:

1. checks the prerequisites above and stops with a pointer to the fix if one is missing;
2. installs the HAProxy ingress controller the Run:ai documentation uses
   (`ingress-nginx` has been retired upstream). Set
   `runai_platform_install_ingress: false` if your site already runs a controller
   and set `runai_platform_ingress_class` to match;
3. creates the TLS secrets. With no certificate given it makes a local CA and a
   certificate for the domain (lab use); for a real site set
   `runai_platform_tls_cert_file`, `runai_platform_tls_key_file` and, if privately
   signed, `runai_platform_ca_file` (paths on the control-plane node);
4. installs the control plane, registers the cluster with it through its API, and
   installs the cluster chart with the short-lived install key the API returns.

**Names.** `runai_platform_domain` must resolve to the ingress address from the
nodes and from wherever you browse. Without DNS (a lab), set
`runai_platform_manage_hosts_entry: true` (hosts-file line on the control-plane
node) and `runai_platform_coredns_rewrite: true` (in-cluster name). Kubespray owns
the CoreDNS settings and overwrites the rewrite on its next run; for a lasting entry
set Kubespray's `dns_etchosts` instead.

Check it (the admin credentials go in the environment, never on the command line):

```bash
RUNAI_USERNAME=admin@example.com RUNAI_PASSWORD='...' \
  python3 scripts/validation/validate_runai.py --json --mode platform \
  --platform-domain runai.example.com --ca-file /opt/deepops/runai/ca.pem \
  --namespace runai-<project> --queue <project>
```

In platform mode, pods must be submitted in a Run:ai project's namespace and use
that project's queue. Either create a project in the web UI (or API) first and pass
its namespace and queue to the validator, or let the validator do it: add
`--create-project deepops-validate` and it creates that project through the API
(one GPU of quota in the first node pool), runs the whole-GPU and half-GPU checks in
`runai-deepops-validate` with `runai-scheduler`, and deletes the project again. With
that flag `"ok": true` also requires the project to have been created and deleted. Beyond what the validator checks, DeepOps
does not configure projects, users or quotas; use the Run:ai documentation.

Run:ai 3.0 releases often. Keep `runai_chart_version` pinned and refresh it on
purpose.

## Remove it

```bash
ansible-playbook -l kube_control_plane playbooks/k8s-cluster/runai.yml -e runai_state=absent
python3 scripts/validation/validate_runai.py --json --verify-uninstalled
```

The second command passes only if no `kai-scheduler`, `kai-resource-reservation`
or `runai*` namespace or Helm release remains. The charts leave some namespaces
and custom resource definitions behind on purpose; the role removes the
namespaces. Add `-e runai_uninstall_remove_crds=true` to remove the definitions
too (this deletes any queues and projects still defined).

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Role stops: "No node advertises nvidia.com/gpu" | GPU stack not ready. Install the GPU Operator and wait for the node to report GPUs. |
| Role stops: "ships its own KAI" | Both modes are installed. Remove one first. |
| Role stops: GPU Operator or `r615` | Fractioning prerequisites missing; see above. |
| Pod stays `Pending` with `schedulerName: kai-scheduler` | No queue label, or the queue does not exist: `kubectl get queues.scheduling.run.ai`. |
| A half-GPU pod is rejected | It also asks for a whole `nvidia.com/gpu`, or the fraction is not between 0 and 1. |
| Validator: scheduler deployments missing | The KAI operator is still starting. Wait a minute and rerun. |
| Platform validator: control plane unreachable | The domain does not resolve to the ingress address, or the CA is not trusted: pass `--ca-file` and `--resolve-ip`. |
