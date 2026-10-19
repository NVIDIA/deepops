---
name: deploy-runai-kai
description: Use when adding or removing the optional KAI Scheduler or Run:ai platform on a DeepOps Kubernetes GPU cluster, enabling fractional-GPU scheduling, or diagnosing KAI/Run:ai install or scheduling failures.
---

# Deploy KAI Scheduler or Run:ai (optional)

Run commands from the DeepOps repository root. This adds GPU-aware scheduling
on top of a working Kubernetes GPU cluster. It is off by default and never changes
the GPU Operator or the NVIDIA driver. Full guide: `docs/k8s-cluster/runai.md`.

## Preconditions

1. `python3 scripts/validation/validate_k8s.py --json --cuda-smoke` reports
   `"ok": true` (the cluster already runs GPU pods). If not, use
   `skills/deploy-k8s-gpu-cluster/` first.
2. Confirm the inventory is the intended cluster and nobody else's workloads run
   there; the install adds cluster-wide admission webhooks.
3. Pick one mode. `kai` and `platform` exclude each other (the platform ships its
   own KAI). `platform` is experimental and also needs a default StorageClass,
   `kube-prometheus-stack` 88.6.5+, a DNS name and TLS (see the guide).
4. Fractioning with hard memory limits (`runai_kai_gpu_fractioning: true`) needs GPU
   Operator v26.7.1+ and an r615+ driver already in place. Do not change the
   default driver to get it without the cluster owner's agreement.

## Procedure

1. Set `runai_mode` (and, for platform, the domain, admin user and a vaulted
   login value) in `config/group_vars/k8s_cluster.yml`.
2. Preview: `ansible-playbook -l kube_control_plane playbooks/k8s-cluster/runai.yml --check --diff`
3. Apply: `ansible-playbook -l kube_control_plane playbooks/k8s-cluster/runai.yml`.
   Rerun once; the second run must report `changed=0`.
4. Verify with the validator, not with the playbook result:

   ```bash
   python3 scripts/validation/validate_runai.py --json                      # kai
   python3 scripts/validation/validate_runai.py --json --memory-enforcement # + fractioning
   ```

   Require exit `0` and `"ok": true` with `gpu_job_ok` and `fraction_job_ok` true.
   Platform mode: add `--mode platform --platform-domain <fqdn>`, set
   `RUNAI_USERNAME`/`RUNAI_PASSWORD` in the environment (never as arguments), and use
   a Run:ai project's namespace and queue.
5. Remove: add `-e runai_state=absent`, then
   `python3 scripts/validation/validate_runai.py --json --verify-uninstalled`
   must report `"ok": true`.

## Failure branches

| Signal | Do |
|---|---|
| Role stops with "No node advertises nvidia.com/gpu" | GPU stack not ready; wait, or run the GPU Operator playbook. Do not bypass with `runai_require_gpu: false` on a real install. |
| Role stops with "ships its own KAI" | Remove the other mode first (`runai_state: absent`). |
| Role stops on GPU Operator version or `r615` | Missing fractioning prerequisites. Set `runai_kai_gpu_fractioning: false`, or ask the cluster owner to approve the GPU stack change. |
| Validator `scheduler deployments missing/not available` | KAI operator still starting; wait and rerun. `kubectl -n kai-scheduler get pods`. |
| `gpu_job_ok` false, pod `Pending` | Wrong queue or none: `kubectl get queues.scheduling.run.ai`; pod must set `schedulerName: kai-scheduler` and the queue label. |
| `fraction_job_ok` false: pods on different GPUs | The node has more than one GPU and KAI chose another; with one GPU this means sharing is off (`global.gpuSharingMode`). |
| `memory_enforcement_ok` false | Limits are not enforced: check the GPU Operator CDI/NRI settings and `kubectl get gpufractioningconfig default -o yaml`. Do not claim enforcement. |
| Platform: control plane unreachable | The domain must resolve to the ingress address; pass `--ca-file`/`--resolve-ip`. |
| Uninstall check lists leftovers | Remove the named namespaces/releases; add `-e runai_uninstall_remove_crds=true` only if queues/projects may be deleted. |

## Do not

- Install standalone KAI beside the Run:ai cluster chart.
- Put the admin login value in a command line, an inventory file in Git, or a log.
- Treat a finished playbook as success; only the validator's `"ok": true` counts.
- Claim a live result you did not run. Offline tests prove the logic, not a GPU job.
