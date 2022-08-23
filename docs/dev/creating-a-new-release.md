# Creating a new DeepOps release

- [Update software versions and dependencies for new release](#update-software-versions-and-dependencies-for-new-release)
  - [Kubespray](#kubespray)
  - [Slurm](#slurm)
  - [Ansible Galaxy dependencies](#ansible-galaxy-dependencies)
  - [Slurm container dependencies](#slurm-container-dependencies)
  - [Helm charts](#helm-charts)
  - [Misc. roles](#misc-roles)
- [Create PR with release notes](#create-pr-with-release-notes)
- [Create release](#create-release)



As of release 22.04, DeepOps no longer utilizes release branches.
All changes should be merged with the main branch and a release tag created.

## Update software versions and dependencies for new release

Create a new pull request against the main branch with changes to version numbers

- Kubespray
- Slurm
- Ansible Galaxy dependencies
- Slurm container dependencies
- Helm charts
- Misc. roles

### Kubespray

Update the Kubespray submodule to the latest version

```bash
cd submodules/kubespray
git fetch --all
git tag -l
# pick the latest tag from the list, i.e.
git checkout v2.15.1
```

### Slurm

Update the `slurm_version` variable in the following files:

  * `config.example/group_vars/slurm-cluster.yml`
  * `roles/slurm/defaults/main.yml`

### Ansible Galaxy dependencies

Update version numbers in the `roles/requirements.yml` file

### Slurm container dependencies

  * Update `prometheus_container` in `roles/prometheus/defaults/main.yml`
  * Update `slurm_exporter_container` in `roles/prometheus-slurm-exporter/defaults/main.yml`
  * Update `node_exporter_container` in `roles/prometheus-node-exporter/defaults/main.yml`
  * Update `grafana_container` in `roles/grafana/defaults/main.yml`
  * Update `alertmanager_container` in `roles/alertmanager/defaults/main.yml`

### Helm charts

  * Update `HELM_INGRESS_CHART_VERSION` in `scripts/k8s/deploy_ingress.sh`
  * Update `HELM_PROMETHEUS_CHART_VERSION` in `scripts/k8s/deploy_monitoring.sh`
  * Update `k8s_gpu_feature_discovery_chart_version` in `roles/nvidia-k8s-gpu-feature-discovery/defaults/main.yml`
  * Update `k8s_gpu_plugin_chart_version` in `roles/nvidia-k8s-gpu-device-plugin/defaults/main.yml`
  * Update `gpu_operator_driver_version` and `gpu_operator_chart_version` in `roles/nvidia-gpu-operator/defaults/main.yml`

### Misc. roles

  * Update `spack_version` in `roles/spack/defaults/main.yml`
  * Update `standalone_container_registry_image` in `roles/standalone-container-registry/defaults/main.yml`
  * Update `cuda_version` in `roles/nvidia_cuda/defaults/main.yml`
  * Update `nvidia_network_operator_version` in `roles/nvidia-network-operator/vars/main.yaml`
  * Update `mig_manager_url_deb` and `mig_manager_url_rpm` in `roles/nvidia-mig-manager/defaults/main.yml`
  * Update `nginx_docker_cache_image` in `roles/nginx-docker-registry-cache/defaults/main.yml`

## Create PR with release notes

Once all pull requests for the release have been merged, including software version updates,
and all QA tests are passing, create a new PR with release notes and an updated release tag
in the main `README.md` file. See [#1164](https://github.com/NVIDIA/deepops/pull/1164) as an example.

## Create release

Once the previous pull request with release notes and tag update has been merged, create a new release
with a new tag, pointing at the main branch and using the release notes from the PR.
