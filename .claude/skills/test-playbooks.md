---
name: test-playbooks
description: Test Ansible playbooks across Ubuntu versions on target machines
---

## Prerequisites
- Virtualenv activated (`source .venv/bin/activate` or `source /opt/deepops/env/bin/activate`)
- Target machines provisioned and accessible via SSH
- Inventory configured: either `config/inventory` (static) or `config/maas-inventory.yml` (MAAS dynamic)

## Steps
1. Verify connectivity: `ansible -m ping all`
2. Run playbook: `ansible-playbook playbooks/<playbook>.yml`
3. Verify results (check playbook output, run smoke tests on targets)
4. To test another OS version: reprovision targets with the new OS, re-run playbook, verify again

## Test Matrix
| Playbook | Inventory groups needed | Test on 24.04 | Test on 22.04 |
|----------|------------------------|---------------|---------------|
| k8s-cluster.yml | kube_control_plane, kube_node, etcd | yes | yes |
| slurm-cluster.yml | slurm-master, slurm-node | yes | yes |
| ngc-ready-server.yml | (any host group) | yes | yes |

## MAAS Users
If using MAAS dynamic inventory (`scripts/maas_inventory.py`), the deploy script automates provisioning:
```bash
./scripts/maas_deploy.sh --status                      # check VM state
./scripts/maas_deploy.sh --os noble --profile k8s      # deploy + tag for K8s
./scripts/maas_deploy.sh --os jammy --profile slurm    # deploy + tag for Slurm
./scripts/maas_deploy.sh --profile k8s --tags-only     # re-tag without redeploying
./scripts/maas_deploy.sh --release                     # release VMs
```
Profiles assign MAAS tags that the dynamic inventory maps to Ansible groups:
- **k8s**: first machine = `kube_control_plane` + `etcd`, remaining = `kube_node`
- **slurm**: first machine = `slurm-master`, remaining = `slurm-node`

## Group Naming
- K8s groups use underscores: `kube_control_plane`, `kube_node`, `k8s_cluster`
- Slurm groups use hyphens: `slurm-master`, `slurm-node`, `slurm-cluster`
- Old hyphenated K8s names (`kube-master`, `kube-node`) are accepted via TAG_ALIASES
