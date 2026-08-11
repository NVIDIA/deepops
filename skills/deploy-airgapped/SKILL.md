---
name: deploy-airgapped
description: Prepare mirrors and transfer artifacts, configure DeepOps, deploy Slurm or Kubernetes GPU clusters without Internet access, and validate them with machine-readable gates. Use for disconnected, restricted-egress, offline, or air-gapped DeepOps installations and for diagnosing missing package, file, chart, or container artifacts.
---

# Deploy DeepOps in an air-gapped environment

## Preconditions and boundaries

- Use an Internet-connected staging machine and a separate provisioning machine
  that can reach every target and every internal mirror. Do not connect an
  isolated network to the Internet for this procedure.
- Fix one DeepOps commit, target OS release, CPU architecture, cluster type,
  inventory, and enabled feature set before mirroring. Repository and image
  requirements change when any of these inputs change.
- Provide complete distribution package mirrors plus internal HTTP package/file
  service and container registry endpoints. Use trusted TLS where possible; if
  the registry is intentionally insecure, configure it explicitly.
- Bootstrap the isolated provisioning machine with the OS packages and Python
  environment required by `scripts/setup.sh` before closing the boundary, or
  provide approved internal OS and Python package indexes. Copying the source
  tree alone does not install Ansible.
- Reserve enough storage for repository metadata, packages, container images,
  charts, the initialized DeepOps checkout, and two copies during transfer.
- Confirm that every target is fully manageable and has no active users or
  workloads. Driver installation can reboot hosts.
- Run DeepOps commands from the repository root. Keep secrets out of archives
  and store site configuration in `config/`, never `config.example/`.

DeepOps does not provide supported mirror-building automation. Do **not** run
`scripts/airgap/build_offline_cache.sh`: it calls the removed
`playbooks/airgap/build-offline-cache.yml` and cannot complete in this tree.
Build and verify the mirrors explicitly as described below.

## 1. Freeze the deployment inputs

1. Record the DeepOps commit and initialize every submodule on the connected
   staging machine:

   ```bash
   git rev-parse HEAD
   git submodule update --init --recursive
   ./scripts/setup.sh
   ```

2. Copy `config.example/` to `config/`. Define the real hosts in
   `config/inventory` before collecting artifacts so the selected cluster path
   and optional components are known:

   - Slurm: controller/login hosts in `[slurm-master]`, compute hosts in
     `[slurm-node]`; a single host may be in both groups.
   - Kubernetes: control-plane hosts in `[kube_control_plane]` and `[etcd]`,
     workers in `[kube_node]`; a single host may be in all three groups.

3. Review the resolved inventory. Stop if it contains any unintended host:

   ```bash
   ansible-inventory -i config/inventory --list
   ```

4. Record the target OS release/architecture and all enabled roles. Mirror
   every dependency of that exact profile. In particular, account for:

   - distribution, Docker CE, NVIDIA CUDA/driver, NVIDIA Container Toolkit,
     and EPEL repositories where applicable;
   - direct-download archives referenced by enabled role defaults;
   - every container image and Helm chart used by the chosen Slurm or
     Kubernetes path;
   - the initialized Kubespray submodule, Galaxy roles/collections, and Python
     packages needed on the provisioning machine.

## 2. Build package mirrors on the connected side

### Ubuntu/APT

Install `apt-mirror`, set `base_path` in `/etc/apt/mirror.list` (for example,
`/var/repos`), and add the suites for the target release. For Ubuntu 24.04
(`noble`), the current DeepOps documentation uses these sources:

```text
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
deb https://download.docker.com/linux/ubuntu noble stable
deb https://nvidia.github.io/libnvidia-container/stable/deb/amd64 /
deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64 /
```

Add DGX OS or MAAS repositories only when the selected profile uses them. Use
the matching suite and architecture instead of `noble`/`amd64` for another
target. Download exactly the configured set:

```bash
sudo mkdir -p /var/repos
sudo apt-mirror
```

Preserve and verify the repository signing keys alongside the mirror, including
the Docker, CUDA, and NVIDIA Container Toolkit keys documented in
`docs/airgap/mirror-apt-repos.md`.

### Enterprise Linux/RPM

Configure the target distribution repositories plus the required EPEL, Docker
CE, CUDA (`cuda-rhel8-x86_64` or `cuda-rhel9-x86_64`),
`libnvidia-container`, and `nvidia-container-toolkit` repositories. Download
each enabled repository ID and generate metadata; repeat these commands for
every ID:

```bash
sudo reposync -l --repoid=docker-ce-stable --downloadcomps \
  --download-metadata --download_path=/var/repos
sudo createrepo /var/repos/docker-ce-stable
```

Do not infer completeness from that example. Compare the final repository IDs
with `/etc/yum.repos.d/` on an Internet-connected reference host configured for
the same workload.

## 3. Mirror direct files, charts, and images

1. Copy direct-download files into the HTTP mirror and override the
   corresponding variables in `config/group_vars/`. For the default Slurm path,
   inspect and account for at least these current variables:

   - `slurm_src_url`, `hwloc_src_url`, and `pmix_src_url`
   - `nhc_src_url` when `slurm_install_nhc: true`
   - `slurm_pyxis_tarball_url` when Enroot/Pyxis is enabled
   - `hpcsdk_download_url` when `slurm_install_hpcsdk: true`
   - `epel_package` **and** `epel_key_url` on Enterprise Linux — several
     default roles import the EPEL GPG key directly from
     `dl.fedoraproject.org`; mirror the key file and override `epel_key_url`
     or the play fails offline at key import
   - `dcgm_deb_package` or `dcgm_rpm_package` when using a locally downloaded
     DCGM package

   The default Slurm configuration also enables CUDA installation, whose
   Ubuntu and Enterprise Linux tasks fetch the CUDA repository and its
   signing material from `developer.download.nvidia.com` through their own
   variables. Mirroring the CUDA packages alone does not redirect these
   tasks; mirror the repository metadata, keyring package, and GPG key, then
   override:

   - `nvidia_driver_ubuntu_cuda_repo_baseurl` and
     `nvidia_driver_ubuntu_cuda_keyring_url` (Ubuntu)
   - `nvidia_driver_rhel_cuda_repo_baseurl` and
     `nvidia_driver_rhel_cuda_repo_gpgkey` (Enterprise Linux)

   Either mirror and override every enabled dependency or explicitly disable
   the optional component. Do not silently fall back to its public URL.

2. Mirror the Helm repositories/charts required by the selected Kubernetes
   profile. The default tree references the stable Helm repository, GPU
   Operator `v26.3.3`, and, when enabled, NFS subdir external provisioner
   `4.0.18`. Set `gpu_operator_helm_repo` and
   `k8s_nfs_client_helm_repo` to internal chart repositories. Read
   `submodules/kubespray/docs/offline-environment.md` from the pinned,
   initialized submodule and mirror its exact file/image list; do not use an
   offline list from a different Kubespray revision.

   Archive the chart versions selected by current DeepOps defaults on the
   connected side:

   ```bash
   mkdir -p /tmp/charts
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
   helm pull nvidia/gpu-operator --version v26.3.3 --destination /tmp/charts
   helm repo add nfs-subdir-external-provisioner \
     https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
   helm pull nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
     --version 4.0.18 --destination /tmp/charts
   helm repo index /tmp/charts
   ```

   Omit the NFS chart only when `k8s_nfs_client_provisioner: false`. Publish
   `/tmp/charts` from an internal HTTP service and set the two repository
   variables to that URL.

3. Determine the container set from a connected reference deployment with the
   same features. Include images used by Kubespray, enabled charts, the GPU
   stack, validation, and any Slurm monitoring/registry roles. Pull and archive
   each image. For the current CUDA validator image:

   ```bash
   mkdir -p /tmp/images
   docker pull nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04
   docker save -o /tmp/images/nvidia-cuda-12.4.1-base-ubuntu22.04.tar \
     nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04
   docker pull registry:3.1.1
   docker save -o /tmp/images/registry-3.1.1.tar registry:3.1.1
   ```

   When Slurm monitoring stays enabled, also mirror the images selected by
   `prometheus_container`, `grafana_container`, `alertmanager_container`,
   `node_exporter_container`, and `nvidia_dcgm_container`, then override those
   variables with their internal registry paths.

4. Archive the initialized checkout separately from site secrets. **Keep
   `.git` in the archive**: `playbooks/k8s-cluster.yml` unconditionally runs
   `git submodule update --init` from the repository root, so an extracted
   tree without Git metadata fails before Kubespray starts. With submodules
   already initialized at the pinned commits, that task is an offline no-op.
   Run this from the checkout's parent directory after `setup.sh` has
   populated its Galaxy dependencies and
   `git submodule update --init --recursive` has completed:

   ```bash
   git -C deepops submodule status --recursive   # every line must start with a space (initialized, pinned)
   tar --exclude='deepops/config' \
     -czf /tmp/deepops-source.tar.gz deepops
   ```

   The archive is larger with Git metadata included; that is the price of the
   Kubernetes path working. Excluding `deepops/config` still keeps site
   secrets out of the transfer artifact.

5. Package repositories and images for approved removable-media transfer and
   create checksums. Substitute a protected, user-owned staging directory for
   `/path/to/staging`; create the ISO files without elevated privileges:

   ```bash
   genisoimage -o /path/to/staging/packages.iso /var/repos
   genisoimage -o /path/to/staging/images.iso /tmp/images
   genisoimage -o /path/to/staging/charts.iso /tmp/charts
   cp /tmp/deepops-source.tar.gz /path/to/staging/
   cd /path/to/staging
   sha256sum packages.iso images.iso charts.iso deepops-source.tar.gz \
     > SHA256SUMS
   ```

Transfer the ISO files, checkout archive, detached signing keys, and checksum
file through the site's approved boundary process. Verify the checksums again
inside the isolated network before importing anything:

```bash
cd /path/to/import
sha256sum -c SHA256SUMS
```

## 4. Import artifacts on the isolated side

1. Mount the verified transfer images and copy their contents to persistent or
   working directories:

   ```bash
   sudo mkdir -p /mnt/deepops-packages /mnt/deepops-images /mnt/deepops-charts
   sudo mount -o loop /path/to/import/packages.iso /mnt/deepops-packages
   sudo mount -o loop /path/to/import/images.iso /mnt/deepops-images
   sudo mount -o loop /path/to/import/charts.iso /mnt/deepops-charts
   sudo mkdir -p /var/repos /var/www/html/charts
   mkdir -p /tmp/images
   sudo cp -a /mnt/deepops-packages/. /var/repos/
   cp -a /mnt/deepops-images/. /tmp/images/
   sudo cp -a /mnt/deepops-charts/. /var/www/html/charts/
   ```

2. Publish extracted APT/RPM content from an internal package server. For the
   minimal Apache layout used by the repository docs:

   ```bash
   sudo mkdir -p /var/www/html/repos
   sudo cp -r /var/repos/mirror/nvidia.github.io/libnvidia-container/ \
     /var/www/html/repos/libnvidia-container/
   ```

   Point Ubuntu targets at the internal `deb` URLs. On Enterprise Linux,
   create repo files with `baseurl=http://<package-server>/repos/<repo-id>` and
   remove/disable upstream `mirrorlist` entries. Preserve GPG verification;
   use `trusted=yes` only when the site's package trust policy explicitly
   permits it.

3. Load the registry image and start the isolated registry if the site does
   not already provide one:

   ```bash
   docker load -i /tmp/images/registry-3.1.1.tar
   docker volume create registry-images
   docker run -d -p 5000:5000 --restart=always --name registry \
     -v registry-images:/var/lib/registry registry:3.1.1
   ```

4. Import, retag, and push every archived image. Preserve the complete path
   expected by the consuming chart or role:

   ```bash
   docker load -i /tmp/images/nvidia-cuda-12.4.1-base-ubuntu22.04.tar
   docker tag nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04 \
     registry-host:5000/nvidia/cuda:12.4.1-base-ubuntu22.04
   docker push registry-host:5000/nvidia/cuda:12.4.1-base-ubuntu22.04
   ```

5. Extract the initialized DeepOps checkout on the provisioning machine:

   ```bash
   mkdir -p /opt/deepops-src
   tar -xzf /path/to/import/deepops-source.tar.gz -C /opt/deepops-src
   cd /opt/deepops-src/deepops
   ```

   Activate the provisioning environment prepared before isolation (or install
   it from approved internal indexes), then copy and edit `config.example/` if
   site configuration was not transferred separately.

## 5. Configure DeepOps for internal endpoints

Set mirror overrides in `config/group_vars/all.yml` (or a narrower group file).
Use values matching the paths actually published by the site:

```yaml
docker_ubuntu_repo_base_url: "http://package-server/repos/docker"
docker_ubuntu_repo_gpgkey: "http://package-server/keys/docker.gpg"
nvidia_container_toolkit_repo_base_url: "http://package-server/repos/libnvidia-container"
nvidia_container_toolkit_repo_gpg_url: "http://package-server/keys/libnvidia-container.gpg"

docker_rh_repo_base_url: "http://package-server/repos/docker"
docker_rh_repo_gpgkey: "http://package-server/keys/docker.gpg"
nvidia_container_toolkit_rpm_repo_url: "http://package-server/repos/nvidia-container-toolkit.repo"

docker_insecure_registries:
  - "registry-host:5000"

# CUDA repository mirror (required by the default Slurm path; see step 3)
nvidia_driver_ubuntu_cuda_repo_baseurl: "http://package-server/repos/cuda-ubuntu"
nvidia_driver_ubuntu_cuda_keyring_url: "http://package-server/repos/cuda-ubuntu/cuda-keyring_1.1-1_all.deb"
nvidia_driver_rhel_cuda_repo_baseurl: "http://package-server/repos/cuda-rhel/"
nvidia_driver_rhel_cuda_repo_gpgkey: "http://package-server/keys/cuda-D42D0685.pub"

# EPEL mirror (Enterprise Linux; key import fails offline without this)
epel_package: "http://package-server/repos/epel/epel-release-latest-9.noarch.rpm"
epel_key_url: "http://package-server/keys/RPM-GPG-KEY-EPEL-9"
```

For Slurm, disable the default pull-through registry cache when upstream
Docker Hub is unreachable. If using the site's registry, the smallest honest
profile is:

```yaml
slurm_enable_container_registry: false
standalone_container_registry_cache_enable: false
```

Mirror and override the Slurm source/archive variables listed above. If their
artifacts were deliberately excluded, disable the corresponding optional
features, for example `slurm_enable_monitoring`, `slurm_install_hpcsdk`,
`slurm_install_nhc`, `slurm_install_enroot`, or `slurm_install_pyxis`. Do not
disable a required feature merely to make a playbook pass.

For Kubernetes, set the pinned Kubespray offline variables from its checked-in
offline guide, internal Helm repository URLs, and internal image registry
rewrites. Set `k8s_nfs_client_provisioner: false` only if the cluster uses a
site-owned storage path or intentionally has no dynamic NFS provisioner.

The current top-level Kubernetes playbook invokes a Helm installer URL and
adds `https://charts.helm.sh/stable`; when the Ansible host platform differs
from the cluster nodes (for example a macOS or arm64 control machine), its
artifact step also downloads `kubectl` and its checksum directly from
`https://dl.k8s.io`. Run the deployment from a control host matching the
cluster platform so the playbook fetches `kubectl` from a cluster node
instead, or pre-approve an internal mirror for that URL. Its containerd
local-registry settings
also carry an explicit TODO in `config.example/group_vars/k8s_cluster.yml`.
Therefore, before declaring a fully disconnected Kubernetes run ready, prove
that these references are satisfied by approved internal endpoints or obtain a
DeepOps code change. Do not claim that the current playbook is turnkey offline.

## 6. Preflight and deploy

Run the machine-readable doctor from the isolated provisioning machine:

```bash
python3 scripts/validation/deepops_doctor.py --remote --json
```

Require exit code `0` and top-level `"ok": true`. Review the reported host
count/groups against the approved inventory. The GPU PCI count is informational;
all other failed checks must be understood and resolved before deployment.

### Slurm path

```bash
ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml
```

Rerun the same command after a transient mirror/package error. Validate on a
Slurm controller, login, or compute node:

```bash
python3 scripts/validation/validate_slurm.py --json
```

Require exit code `0`, `"ok": true`, `"nodes_unavailable": 0`,
`"gpus_configured"` greater than zero, and `"gpu_job_ok": true`.

### Kubernetes path

Run only after all Kubernetes package, file, chart, and image references have
been resolved to the isolated environment:

```bash
ansible-playbook -l k8s_cluster playbooks/k8s-cluster.yml
```

Validate from a machine whose `kubectl` context reaches the cluster, overriding
the public default CUDA image with the imported registry image:

```bash
python3 scripts/validation/validate_k8s.py --json --cuda-smoke \
  --cuda-image registry-host:5000/nvidia/cuda:12.4.1-base-ubuntu22.04
```

Require exit code `0`, `"ok": true`, `nodes_ready == nodes_total`,
`"gpus_allocatable"` greater than zero, `"cuda_smoke_ok": true`, and
`"cuda_smoke_gpus"` greater than zero. A play recap with `failed=0` is not
the success gate.

## Cleanup

- On Kubernetes smoke success, the validator deletes the temporary
  `deepops-validate` namespace automatically. On failure it deliberately keeps
  the namespace for diagnosis; delete it only after collecting evidence:

  ```bash
  kubectl delete namespace deepops-validate --ignore-not-found
  ```

- Unmount/eject approved transfer media and remove temporary extracted copies
  only after checksums, repository reachability, image pulls, and the required
  validation record have been captured:

  ```bash
  sudo umount /mnt/deepops-packages
  sudo umount /mnt/deepops-images
  sudo umount /mnt/deepops-charts
  ```

  Do not remove the internal mirrors or registry: deployed nodes continue to
  need them for repairs and rescheduling.
- Remove secrets and site inventory from transfer staging. Retain the manifest,
  checksums, exact DeepOps commit, mirror snapshot/version, play recap, and
  validator JSON according to site policy.

## Observed failure branches

- **`build_offline_cache.sh` fails because
  `playbooks/airgap/build-offline-cache.yml` is missing:** this automation was
  removed as broken/unsupported. Use the explicit mirror workflow above.
- **Doctor reports `kubespray_submodule_initialized: false`, or Kubernetes
  fails on `kubespray_defaults` imports:** transfer an archive made after
  `git submodule update --init --recursive`; do not fetch from the isolated
  side.
- **Package task tries a public URL or reports a missing package:** the mirror
  set or variable override is incomplete for the enabled profile. Add the exact
  repository/file to the connected-side manifest, transfer a new signed
  snapshot, and rerun the same idempotent playbook.
- **Slurm play reaches GitHub, SchedMD, Open MPI, or NVIDIA download hosts:**
  mirror and override the applicable source URL, or intentionally disable the
  optional NHC, Pyxis, HPC SDK, or monitoring component.
- **Bare `nvidia-smi` over SSH reports `No devices were found` on a Slurm
  node:** DeepOps may hide GPUs from ordinary SSH sessions. Trust the
  validator's `srun` job; do not diagnose the driver from the bare SSH result.
- **Slurm validator reports `gpu_job_ok: false`:** inspect its `failures` list.
  If it reports driver errors, follow `skills/diagnose-driver-install/`; if the
  node is down/drained, inspect its Slurm reason before resuming it.
- **Kubernetes play tries `raw.githubusercontent.com`,
  `charts.helm.sh/stable`, a public chart repo, or a public image registry:**
  stop. The pinned Helm/chart/image dependency is not yet served internally;
  complete that mirror or gate the required DeepOps change before rerunning.
- **Kubernetes CUDA smoke is `Pending` or shows an image pull error:** confirm
  the `--cuda-image` path exists in the internal registry and is reachable by
  every GPU node. Inspect the retained `deepops-validate` namespace before
  cleanup.
- **Kubernetes reports `gpus_allocatable: 0`:** wait for the mirrored GPU stack
  to become ready, then diagnose GPU Operator/device-plugin or driver failures.
  Do not use `--allow-no-gpus` as a deployment success gate for a GPU cluster.
- **A rerun uses facts from a reprovisioned/reused hostname:** add
  `--flush-cache` to the same playbook command.
