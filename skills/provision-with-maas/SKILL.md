---
name: provision-with-maas
description: Provision or reinstall bare-metal servers and test VMs through Canonical MAAS, map deployed machines into DeepOps Ansible inventory with MAAS tags, validate access, or release them safely. Use when operating DeepOps with a MAAS-owned machine lifecycle.
---

# Provision with MAAS

Keep MAAS authoritative for machine lifecycle, power, PXE/DHCP, OS images,
commissioning, deployment, release, pools, zones, and tags. Use DeepOps to
install a controller, request explicit deploy/tag/release operations, and turn
deployed machine tags into Ansible inventory.

## Preconditions

- Work from the DeepOps repository root on a prepared Ansible control machine.
- Confirm that every target is authorized for reinstallation. A deploy erases
  its installed OS, and `maas_deploy.sh` releases every listed deployed machine
  before installing it again.
- Provide a MAAS 3.x controller reachable through its REST API and an OAuth1
  API key in `consumer_key:token_key:token_secret` format.
- Ensure the provisioning VLAN can safely use MAAS DHCP, with a reserved
  dynamic range that does not overlap site addresses. Targets must PXE boot on
  that network.
- Configure target power control in MAAS, or arrange manual power cycles.
  Commission each target to `Ready`, sync the requested Ubuntu image, and add
  an SSH public key that the operator can use after deployment.
- Use Ubuntu 24.04 with the MAAS 3.7 repository for a new controller, or the
  MAAS 3.5 repository while the controller remains on Ubuntu 22.04.

## Procedure

### Prepare MAAS and DeepOps

1. Install DeepOps dependencies and create the private configuration if this
   checkout has not been prepared:

   ```bash
   ./scripts/setup.sh
   ```

2. If DeepOps must install the MAAS controller, set `maas_adminusers`,
   `maas_dns_domain`, `maas_region_controller`,
   `maas_region_controller_url`, and `maas_repo` in
   `config/group_vars/all.yml`. Review the inventory, then limit the
   controller playbook to exactly that host:

   ```bash
   ansible-playbook -l <maas-controller-host> playbooks/provisioning/maas.yml
   ```

   Skip this step when using an existing MAAS controller.

3. Edit `config/maas-inventory.yml`, which `scripts/setup.sh` creates from
   `config.example/maas-inventory.yml`:

   ```yaml
   api_url: "http://maas-server:5240/MAAS/api/2.0"
   api_key: "consumer_key:token_key:token_secret"
   ssh_user: "ubuntu"
   network: "192.0.2"
   ssh_bastion: "user@bastion-host"
   machines: "node01 node02 node03"
   ```

   Omit `network` for first-address selection and `ssh_bastion` for direct
   access. Set `machines` to the exact MAAS hostnames this operation owns; do
   not rely on the script's test-VM defaults. Environment variables override
   the file. `MAAS_INVENTORY_CONFIG` selects another inventory config for the
   Python inventory script; the deploy script always reads the repo-local file
   but accepts `MAAS_API_URL`, `MAAS_API_KEY`, `MAAS_MACHINES`,
   `MAAS_SSH_USER`, `MAAS_NETWORK`, and SSH proxy overrides.

4. Review the resolved targets and their current state before any mutation:

   ```bash
   MAAS_MACHINES="node01 node02 node03" ./scripts/maas_deploy.sh --status
   ```

   Require every intended hostname to appear. Check status, IP, OS, and tags;
   stop if an unexpected machine is present.

### Map MAAS tags to inventory

`scripts/maas_inventory.py` includes only machines whose MAAS status code is
`6` (`Deployed`). It uses each hostname as the Ansible host and maps every
MAAS tag to an Ansible group. Tag leaf groups; the script creates the DeepOps
parent/child relationships.

Use these canonical role tags:

| Cluster | MAAS leaf tags |
|---------|----------------|
| Kubernetes | `kube_control_plane`, `kube_node`, `etcd` |
| Slurm | `slurm-master`, `slurm-node`, optionally `slurm-nfs`, `slurm-cache`, `slurm-metric`, `slurm-login` |

Legacy `kube-master`, `kube-node`, and `k8s-cluster` tags are accepted and
aliased to canonical group names. The deploy helper does not remove these
legacy tags when applying a profile, so remove them manually in MAAS before a
role change. Otherwise a target can remain in Kubernetes inventory groups after
switching to the Slurm profile. Other tags become same-named Ansible groups.

For the built-in profiles, ordering is significant: the first hostname in
`machines` becomes the Kubernetes control-plane/etcd node or Slurm master;
the remaining hosts become Kubernetes or Slurm workers. Apply or change a
profile without reinstalling:

```bash
MAAS_MACHINES="node01 node02 node03" \
  ./scripts/maas_deploy.sh --profile k8s --tags-only
```

Before applying the profile, this command removes the canonical Kubernetes and
Slurm test tags from every listed target. It does not remove legacy Kubernetes
tags or unrelated MAAS tags. Use MAAS directly for a custom role layout, for
example:

```bash
maas admin tag update-nodes slurm-master add=<node01-system-id>
maas admin tag update-nodes slurm-node add=<node02-system-id> add=<node03-system-id>
```

### Deploy

Run only after reviewing the exact targets and accepting a reinstall of all of
them:

```bash
MAAS_MACHINES="node01 node02 node03" \
  ./scripts/maas_deploy.sh --os noble --profile slurm
```

Use `--os jammy` for Ubuntu 22.04. The default is `noble`. The script:

1. Resolves every hostname to a MAAS system ID and stops if any is absent.
2. Releases deployed machines and waits up to 600 seconds for every machine to
   reach `Ready`.
3. Requests deployment of the selected Ubuntu series and waits up to 600
   seconds for every machine to reach `Deployed`.
4. Selects an IP matching `network`, falling back to the first MAAS address,
   and waits up to 120 seconds for SSH as `ssh_user`.
5. Reports `lsb_release -ds`, then clears known test tags and applies the
   selected profile.

For manual power control, perform each power-on requested by MAAS while the
script is waiting.

### Validate after provisioning

1. Confirm MAAS state, selected IPs, OS, and tags:

   ```bash
   MAAS_MACHINES="node01 node02 node03" ./scripts/maas_deploy.sh --status
   ```

   Require every target to show `Deployed`, the requested Ubuntu release, a
   usable target-network IP, and the intended role tags.

2. Inspect the dynamic inventory before running a cluster playbook:

   ```bash
   ./scripts/maas_inventory.py --list
   ansible-inventory -i scripts/maas_inventory.py --graph
   ```

   Require exactly the intended deployed machines in `all`, the expected leaf
   groups, and the correct first-host/worker split. Inspect `ansible_host` and
   `maas_*` host variables in `--list` when anything is unexpected.

3. Prove Ansible can reach every inventoried machine:

   ```bash
   ansible -i scripts/maas_inventory.py all -m ping
   ```

   Require `SUCCESS` and `"ping": "pong"` for every target. This validates
   provisioning and control-plane access; it does not validate a Slurm or
   Kubernetes deployment.

### Reruns and role changes

- Rerun `--status`, inventory inspection, and Ansible ping freely; they do not
  request lifecycle changes.
- Use `--tags-only` to change between the built-in Kubernetes and Slurm layouts
  without reinstalling. Recheck hostname ordering first because it selects the
  control-plane or master node. Inspect each target for legacy `kube-master`,
  `kube-node`, or `k8s-cluster` tags and remove them manually in MAAS before the
  change; `--tags-only` does not clear them.
- Treat a rerun of the deploy command as a fresh reinstall, not an idempotent
  resume. It releases all listed deployed machines, including machines that
  succeeded during a partially failed multi-machine run.
- A released machine that is still commissioned and `Ready` can be deployed
  again without commissioning it again.

### Cleanup

Release only the exact machines owned by the operation:

```bash
MAAS_MACHINES="node01 node02 node03" ./scripts/maas_deploy.sh --release
```

Require `All machines released.` and verify `--status` shows `Ready`. Released
machines disappear from dynamic inventory because it includes only `Deployed`
machines. Release does not clear their MAAS tags; remove residual role tags in
MAAS separately if the machines are being reassigned, after confirming tag
ownership.

## Failure branches

- **Inventory returns only an empty `_meta` object without an error:** the
  configuration is missing or still contains example placeholders. Populate
  `api_url` and `api_key`, or set the matching environment variables, then
  rerun `--list`.
- **`ERROR: MAAS_API_URL not configured` or `ERROR: MAAS_API_KEY not
  configured`:** populate the missing deploy configuration or its environment
  override. The deploy helper does not use the inventory helper's graceful
  empty-inventory behavior.
- **`MAAS API error: 401`:** replace or correct `MAAS_API_KEY`. If the deploy
  helper reports that the key must use
  `consumer_key:token_key:token_secret`, correct its three-part format before
  making another request.
- **`MAAS connection error`:** verify `MAAS_API_URL` and reachability from the
  control machine. Do not continue to lifecycle operations until inventory or
  status reads succeed.
- **`Machine '<name>' not found in MAAS`:** compare `machines` or
  `MAAS_MACHINES` with MAAS hostnames. Correct the target list; do not replace
  it with a broader list.
- **Inventory is valid but a target is absent:** only `Deployed` machines with
  a non-empty hostname are included. Check `--status`; finish deployment, or
  expect a released/`Ready` machine to remain absent.
- **Inventory chooses the wrong address or SSH times out after 120 seconds:**
  set `network`/`MAAS_NETWORK` to the target subnet, verify `ssh_user`, the
  imported MAAS SSH key, and `ssh_bastion` or proxy settings, then rerun the
  read-only ping checks. A machine with no MAAS address cannot yield a usable
  `ansible_host`.
- **A machine does not reach `Ready` or `Deployed` within 600 seconds:** inspect
  its MAAS state and events. For manual power, perform the requested power
  cycle. If PXE never begins, verify PXE boot and that DHCP is enabled on the
  correct VLAN with a non-overlapping dynamic range. Rerun deployment only
  after deciding whether reinstalling every listed target is acceptable.
- **`--tags-only` fails immediately:** supply `--profile k8s` or
  `--profile slurm`; other profile names are rejected. If groups are still
  wrong, inspect tag names and target ordering. Remove legacy `kube-master`,
  `kube-node`, and `k8s-cluster` tags manually in MAAS because reapplying a
  profile will not clear them; then reapply the intended profile and regenerate
  inventory.
