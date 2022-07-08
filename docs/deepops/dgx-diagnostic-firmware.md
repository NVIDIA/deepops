# DGX Diagnostic Firmware

- [DGX Diagnostic Firmware](#dgx-diagnostic-firmware)
  - [Prerequisites](#prerequisites)
  - [Setup](#setup)
  - [Collect Diagnostics](#collect-diagnostics)
  - [Considerations For Updating Large Clusters](#considerations-for-updating-large-clusters)
  - [Performing the Firmware Update](#performing-the-firmware-update)

The [`nvidia-dgx-firmware`](../../roles/nvidia-dgx-firmware) role has been built to perform several administrative tasks cluster-wide.

1. Upgrade the the DGX firmware (_DGX only clusters_)
2. Run system diagnostics and collect a log bundle (_DGX and non-DGX clusters_)

While documentation exists to [run system health checks](https://docs.nvidia.com/dgx/dgx1-fw-container-release-notes/index.html) and update [DGX firmware](https://docs.nvidia.com/dgx/dgx1-fw-container-release-notes/index.html), this role and document is meant to give guidance on performing these operations cluster-wide using `Ansible` for automation.

## Prerequisites

Before running either the diagnostic or the firmware upgrade playbooks, please ensure the following conditions are true on each node where you plan to run:

- No user workloads should be running on the node
- The firmware update container has been downloaded
- DeepOps is correctly configured as outlined in the [Setup section](#setup)
- DGX OS is installed to the minimum revision listed in the release notes of the firmware update container to be used

**In addition, please ensure that any system services that access the GPU have been stopped.**
The firmware update process should attempt to stop a standard list of services which are provided in DGX OS, including
`dcgm-exporter`, `nvidia-dcgm`, `nvidia-fabricmanager`, `nvidia-persistenced`, `xorg-setup`, `lightdm`, `nvsm-core`, and `kubelet`.
However, if any of these services were launched via Docker, or if you have installed additional services which access the GPU,
those services will need to be stopped manually in advance of running this playbook.

## Setup

Ensure that the playbook is being executed from an admin node where the `scripts/setup.sh` script has already been run and the inventory file is properly configured with DGX nodes all listed under the `slurm-node` group. Refer to the [DeepOps Slurm Deployment Guide](../slurm-cluster/) for details.

If running on a DGX cluster, it is necessary to provide the DGX firmware container in order to gather installed firmware information or perform firmware updates. If running on a non-DGX cluster skip this first step and set `load_firmware` and `update_firmware` to `false`.

Before beginning the update process, make sure to consult the release notes for the DGX firmware container version you plan to use for the update.
The release notes may specify a minimum release of DGX OS necessary to perform the update,
or may have additional instructions related to specific updates in this release.

1. Download the latest [DGX firmware container](https://docs.nvidia.com/dgx/dgxa100-fw-container-release-notes/index.html) in `tar.gz` format, and put the file in `config/containers/dgx-firmware`, keeping the original file name. Add the following variables to `config/group_vars/all.yml` yaml file, reflecting the version being used.

```yml
# The Docker repo name.
# This will depend on the DGX system type being updated, e.g. DGX A100.
firmware_update_repo: nvfw-dgxa100

# The Docker tag
firmware_update_tag: 21.11.4

# The tarball name
firmware_update_container: "nvfw-dgxa100_21.11.4_211111.tar.gz"
```

2. Change the `nv_mgmt_interface` variable to reflect the systems being collected from. The example interface names below should be true in most cases, but make sure to use specify the actual network interface in use on the systems being updated.

```yml
# The OS/mgmt interface on the server
# nv_mgmt_interface: enp1s0f0 # DGX-1
# nv_mgmt_interface: enp134s0f0 # DGX-2
nv_mgmt_interface: enp225s0f0 # DGX A100
# nv_mgmt_interface: enp2s0f1 # DGX-Station
```

> Note: This playbook is meant to run on a system running the DGX OS or a system that has had the nvidia-dgx role applied to it. Certain diagnostics may fail if this is not the case.

## Collect Diagnostics

The [nvidia-dgx-diag.yml](../../playbooks/nvidia-dgx/nvidia-dgx-diag.yml) playbook leverages the [nvidia-dgx-firmware](../../roles/nvidia-dgx-firmware) role to run a diagnostic. This will collect health and configuration information for all nodes across a cluster. After being executed all logs will be copied locally to the provisioning system at `config/logs`. Logs are stored by hostname with timestamps. To change where logs are stored change the `local_log_directory` variable.

**Important:** The diagnostic playbook requires the presence of the firmware update container image in order to successfully validate the expected firmware versions.
It cannot be run without the firmware update container image.

Diagnostics include the following and can easily be expanded by adding tasks to the [run-diagnostics.yml](../../roles/nvidia-dgx-firmware/tasks/run-diagnostics.yml) file:

- Running `nvsm show health`
- Running `nvsm dump health` and gathering logs
- Running `dcgmi diag -r 1` or `dcgmi diag -r 3` if `dcgm_stress: true`
- Collecting `syslog`, `dmesg`, and various other logs
- Collecting InfiniBand configuration
- DGX firmware versions
- Mapping hostnames to BMC/host MAC and IP addresses

This tool can be used to:

- Verify cluster health
- Debug a known issue
- Generate a report bundle for NVIDIA support

Setting `dcgmi_stress` to true will run the dcgm diagnostic at a level of instead of `3` the default of `1`. This can be used as a light system stress test and may take up to 20 minutes to complete. `nvsm dump health` can also take up to 15 minutes to complete and may be disabled by setting `nvsm_dump_health` to `false`. These tests can potentially be disruptive or fail to complete if there are existing issues, it is not recommended to run them while the nodes are in use, see [the official docs](https://docs.nvidia.com/datacenter/nvsm/nvsm-user-guide/index.html) for additional details.

Because this is a debugging tool Ansible will continue executing tasks on all hosts even if some of the tasks fail. It will execute each step with "best-effort" to gather as much health information as possible. This role is designed to be executed against a homogeneous cluster of DGX systems (all DGX-1, all DGX-2, or all DGX A100), but the majority of the functionality will be effective on any GPU cluster. If running on a non-DGX cluster there will be errors and warnings for the DGX specific tasks.

Logs will temporarily be stored in `fw_dir` on the remote machines and will be cleaned up at the end of the playbook. The default remote log dir is `/opt/deepops/nvfw`.

Run the diagnostics playbook:

```bash
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
# NOTE: We specify the connection type as paramikio_ssh to collect stdout from the firmware container
# NOTE: Forks is specified as the number of nodes in the batch (40), allowing each DGX to run commands in parallel
# Collect diagnostic info
ansible-playbook -l slurm-node --connection=paramiko_ssh --forks 40 playbooks/nvidia-dgx/nvidia-dgx-diag.yml
```

> Note: The below tasks may take 15+ minutes per DGX; the playbook will timeout if it is errored or hung, do not cancel the playbook while it is running.

```console
TASK [nvidia-dgx-firmware : Run NVSM human-readable health show] *******************************************************
changed: [dgx]

TASK [nvidia-dgx-firmware : Run NVSM dump health] **********************************************************************
changed: [dgx]
```

After running the diagnostics look for issues by running:

```bash
# Check for failed  NVSM health checks
grep Unhealthy config/logs/*/*nvsm-show-health.log

# Check for failed DCGMI health checks
cat config/logs/*/*dcgm_diag_*.log

# Search for out-of-date DGX firmware versions
grep no config/logs/*/*fw-versions-post-check.log
```

## Considerations For Updating Large Clusters

Avoid running firmware updates on DGX nodes which are actively running user workloads.
When updating the firmware in DGX clusters, first make sure that the nodes being updated have been drained in your job scheduling system.

- If using Kubernetes, [safely drain each node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/) to be updated using `kubectl drain <node-name>`
- If using Slurm, drain the nodes to be updated using `scontrol update node=<node-list> state=drain reason="firmware upgrade"`

For large DGX clusters, it is recommended to first perform a single manual firmware update and verify that node before using any automation cluster-wide. Before running through any firmware update steps, it is recommended to first run through the diagnostics playbook to collect a snapshot of the cluster status.

After verifying that a single node can be successfully upgraded, upgrade the rest of the cluster with the Ansible automation. For larger clusters it is recommended to do this in batches. Perform an initial test of the provisioning node by updating a single node with Ansible and then deploy in batches of ~40 nodes. It is not necessary to do this, but in the case of an error or outage in the provisioning node this will reduce risk of firmware upgrade failure.

For very large clusters it is not uncommon for some nodes to fail to update. This can occur for several reasons such as timeouts or networking issues. When this occurs manually inspect the logs, run an `nvsm show health` and if healthy attempt to re-run the playbook on those nodes. If failures persist contact NVIDIA support and attempt the upgrade manually.

## Performing the Firmware Update

The [nvidia-dgx-fw-update.yml](../../playbooks/nvidia-dgx/nvidia-dgx-fw-update.yml) playbook leverages the [nvidia-dgx-firmware](../../roles/nvidia-dgx-firmware) role to update the DGX firmware.

This will do the following:

- Copy and load the firmware container to all hosts
- Run a pre-update diagnostic (this can be disabled by setting `run_diagnostics` to `false`)
- Determine which nodes are running out-of-date firmware
- Update the firmware on all nodes
- Reboot nodes as required
- Run a post-update diagnostic
- Transfer all logs to the provisioning node
- List nodes that require a manual power cycle.

The release notes for the DGX firmware update container should include a table of updates included in the container, and the expected time to update each component.
Depending on the firmware updates being performed, the update process may take 1-4 hours to complete.

Run the firmware update playbook:

```bash
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-u ubuntu`
# NOTE: We specify the connection type as paramikio_ssh to collect stdout from the firmware container

# Update all firmware
ansible-playbook -l slurm-node --connection=paramiko_ssh --forks 40 playbooks/nvidia-dgx/nvidia-dgx-fw-update.yml

# Reset the BMC on all nodes after a BMC firmware update
ansible slurm-node --forks 40 -ba "ipmitool mc reset cold"
```

Updating firmware might require rebooting the systems, depending on what portion of the firmware is being updated. This is done automatically by the playbooks. However, certain components require a system power cycle. This can be disruptive and must be done manually. Follow the guidance in playbook output to safely shutdown these nodes and power cycle them through the BMC. If the Playbook output does not end with a message indictating a power cycle is needed, this step may be skipped.

> Note, power cycling an entire datacenter's worth of DGX nodes may trigger a datacenter power alarm or trip a breaker. It is recommended to power cycle systems in batches with a several minute delay in-between or to alert the operations team when performing these actions.

To upgrade only a single component, set the `target_fw` variable. To downgrade a component set the `force_update` flag. To update the Standby or Inactive components set the `inactive_update` flag. For example, to use an older firmware container version and downgrade the SBIOS run Ansible with `-e target_fw=SBIOS -e force_update=true` or to upgrade the backup BMC `-e target_fw=BMC -e inactive_update=true`.

> Note: This playbook is designed to only allow upgrading of a single component or all components per run; the recommended best-practice is to run `update_fw all`, however when updating individual components it is best to perform some level of manual verification over the logs after each update.

> Note: It is not a requirement, but to resolve any potential issues while staff are on-site it is recommended to reboot all DGX Nodes after extensive firmware and software updates.

> Note: As shown, the `-l` flag can be used to limit these operations to a single group or single node
