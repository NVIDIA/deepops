# NVIDIA Diagnostics & DGX Firmware Upgrades

The `nvidia-dgx-firmware` role has been built to perform several administrative tasks cluster-wide.

1. Upgrade the the DGX firmware (*DGX only clusters*)
2. Run system diagnostics and collect a log bundle (*DGX and non-DGX clusters*)

While documentation exists to [run system health checks](https://docs.nvidia.com/dgx/dgx1-fw-container-release-notes/index.html) and update [DGX firmware](https://docs.nvidia.com/dgx/dgx1-fw-container-release-notes/index.html), this role and document is meant to give guidance on performing these operations cluster-wide using `Ansible` for automation.


## Setup

If running on a DGX cluster, it is necessary to provide the DGX firmware container in order to gather installed firmware information or perform firmware updates. If running on a non-DGX cluster skip this first step and set `load_firmware` and `update_firmware` to `false`.

1. Download the latest [DGX firmware container](https://docs.nvidia.com/dgx/dgxa100-fw-container-release-notes/index.html) and put it in `src/containers/dgx-firmware`, keeping the original file name. Update the role variables to reflect the version being used.

```yml
# The Docker repo name
firmware_update_repo: nvfw-dgxa100

# The Docker tag
firmware_update_tag: 20.05.12.5

# The tarball name
firmware_update_container: "nvfw-dgxa100_20.10.9_201103.tar.gz"
```

2. Change the `nv_mgmt_interface` variable to reflect the systems being collected from.

```yml
# The OS/mgmt interface on the server
# nv_mgmt_interface: enp1s0f0 # DGX-1
# nv_mgmt_interface: enp134s0f0 # DGX-2
nv_mgmt_interface: enp225s0f0 # DGX A100
# nv_mgmt_interface: enp2s0f1 # DGX-Station
```

> Note: This playbook is meant to run on a system running the DGX OS or a system that has had the nvidia-dgx role applied to it. Certain diagnostics may fail if this is not the case.


## Collect Diagnostics

The `nvidia-dgx-diag.yml` playbook leverages the `nvidia-dgx-firmware` role to run a diagnostic. This will collect health and configuration information for all nodes across a cluster. After being executed all logs will be copied locally to the provisioning system at `config/logs`. Logs are stored by hostname with timestamps. To change where logs are stored change the `local_log_directory` variable.

Diagnostics include the following and easily be expanded by adding tasks to the `run-diagnostics.yml` file:

* Running `nvsm show health`
* Running `nvsm dump health` and gathering logs
* Running `dcgmi diag -r 1`  or `dcgmi diag -r 3` if `dcgm_stress: true`
* Collecting `syslog`, `dmesg`, and various other logs
* Collecting InfiniBand configuration 
* DGX firmware versions
* Mapping hostnames to BMC/host MAC and IP addresses

This tool can be used to:

* Verify cluster health
* Debug a known issue
* Generate a report bundle for NVIDIA support

Setting `dcgmi_stress` to true will run the dcgm diagnostic at a level of instead of the default of 1. This can be used as a light system stress test and may take up to 20 minutes to complete. `nvsm dump health` can also take up to 15 minutes to complete and may be disabled by setting `nvsm_dump_health` to `false`. These tests can potentially be disruptive or fail to complete if there are existing issues, it is not recommended to them while the nodes are in use,  see [the official docs](https://docs.nvidia.com/datacenter/nvsm/nvsm-user-guide/index.html) for additional details. 

Because this is a debugging tool Ansible will continue executing tasks on all hosts even if some of the tasks fail. It will execute each step with "best-effort" to gather as much health information as possible. This role is designed to be executed against a homogeneous cluster of DGX systems (all DGX-1, all DGX-2, or all DGX A100), but the majority of the functionality will be effective on any GPU cluster. If running on a non-DGX cluster there will be errors and warnings for the DGX specific tasks.

Logs will temporarily be stored in `fw_dir` on the remote machines and will be cleaned up at the end of the playbook. The default remote log dir is `/opt/deepops/nvfw`. 

Run the diagnostics playbook:
```sh
# collect diagnostic info
ansible-playbook -l slurm-node playbooks/nvidia-dgx/nvidia-dgx-diag.yml
```

After running the diagnostics, it may be helpful to do a quick scan for issues by running:

```sh
# Check for failed  NVSM health checks
grep Unhealthy config/logs/*/*nvsm-show-health.log

# Check for failed DCGMI health checks
cat config/logs/*/*dcgm_diag_*.log

# Search for out-of-date DGX firmware versions
grep no config/logs/*/*fw-versions-post-check.log
```


## Update Firmware

The `nvidia-dgx-fw-update.yml` playbook leverages the `nvidia-dgx-firmware` role to update the DGX firmware.

This will do the following:

* Copy and load the firmware container to all hosts
* Run a pre-update diagnostic (this can be disabled by setting `run_diagnostics` to `false`)
* Determine which nodes are running out-of-date firmware
* Update the firmware on all nodes
* Reboot nodes as required
* Run a post-update diagnostic
* Transfer all logs to the provisioning node
* List nodes that require a manual power cycle.

For large DGX clusters, it is recommended to first perform a single manual firmware update and verify that node before using any automation cluster-wide.

After verifying a single node can be successfully upgraded, upgrade the rest of the cluster with the Ansible automation. For larger clusters it is recommended to do this in batches. Perform an initial test of the provisioning node by updating a single node with Ansible and then deploy in batches of ~40 nodes. It is not necessary to do this, but in the case of an error or outage in the provisioning node this will reduce risk of firmware upgrade failure.

Depending on the number of nodes and the required firmware updates, this process can take 1-4 hours to complete. For very large clusters it is not uncommon for some nodes to fail to update. This can occur for several reasons such as timeouts or networking issues.  When this occurs manually inspect the logs, run an `nvsm show health` and if healthy attempt to re-run the playbook on those nodes. If failures persist contact NVIDIA support and attempt the upgrade manually.

Updating firmware might require rebooting the systems (depending on what portion of the firmware is being updated). This is done automatically by the playbooks. However, certain components require a system power cycle. This can be disruptive and must be down manually. Follow the guidance in playbook output to safely shutdown these nodes and power cycle them through the BMC.

> Note, power cycling an entire datacenter's worth of DGX nodes may trigger a datacenter power alarm or trip a breaker. It is recommended to power cycle systems in batches with a several minute delay in-between or to alert the operations team when performing these actions.

Run the firmware update playbook:

```sh
# update all firmware
ansible-playbook -l slurm-node playbooks/nvidia-dgx/nvidia-dgx-fw-update.yml

# reset the BMC on all nodes after a BMC firmware update
ansible slurm-node -ba "ipmitool mc reset cold"
```

> Note: This playbook is designed to only allow upgrading of a single component or all components per run; the recommended best-practice is to run `update_fw all`, however when updating individual components it is best to perform some level of manual verification over the logs after each update.

> Note: It is not a requirement, but to resolve any potential issues while staff are on-site it is recommended to reboot all DGX Nodes after extensive firmware and software updates.

> Note: As shown, the `-l` flag can be used to limit these operations to a single group or single node
