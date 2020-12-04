# nvidia-dgx-firmware role

This role makes use of the NVIDIA DGX firmware container and can be used to:
1. Collect health & configuration diagnostics
2. Update the firmware

## Setup

1) Download the latest [DGX firmware container](https://docs.nvidia.com/dgx/dgxa100-fw-container-release-notes/index.html) and put it in `src/containers/dgx-firmware`. Keep the original file name. Update the role variables to reflect the version being used. 

```yml
# The Docker repo name
firmware_update_repo: nvfw-dgxa100

# The Docker tag
firmware_update_tag: 20.05.12.5
```

2) Change the `nv_mgmt_interface` variable to reflect the systems being collected from.

```yml
# The OS/mgmt interface on the server
# nv_mgmt_interface: enp1s0f0 # DGX-1
# nv_mgmt_interface: enp134s0f0 # DGX-2
# nv_mgmt_interface: enp225s0f0 # DGX A100
nv_mgmt_interface: enp2s0f1 # DGX-Station
```

> Note: This role is meant to run on a system running the DGX OS or a system that has had the nvidia-dgx role applied to it.

## Collect Diagnostics

This role can be used to collect health and configuration information across a cluster. This is useful in verifying the health of a cluster or to debug a known issue. Because this is a debugging tool Ansible will continue executing tasks on all hosts even if some of the tasks fail.

Although this role is meant to be executed against a homogeneous cluster of DGX systems (all DGX-1, all DGX-2, or all DGX A100), the majority of the functionality will be effective on any GPU cluster.

### Running

The default behavior is to collect diagnostics. To disable, change the `run_diagnostics` variable...

```yml
run_diagnostics: false
```

Along with general logs and firmware versions, the default behavior will also run `nvsm show health`, `nvsm health dump`, and `dcgmi diag -r 1`. A more extensive dcgmi stress test can be enabled with `dcgmi_stress` and the health dump can be disabled by setting `nvsm_dump_health: false`. These tests can take a long time to complete and be potentially disruptive or fail to complete if there are existing issues. See [the official docs](https://docs.nvidia.com/datacenter/nvsm/nvsm-user-guide/index.html) for additional details. 


Logs will be copied locally to `config/logs`. After running the diagnostics, it may be helpful to do a quick scan for issues by running:

```sh
grep Unhealthy config/logs/*/*nvsm-show-health.log
cat config/logs/*/*dcgm_diag_1.log
# cat config/logs/*/*dcgm_diag_3.log # If `dcgm_stress: true`
```

### Collected Information

All logs will be stored locally in `config/logs`. Logs are stored by hostname with timestamps. To change where logs are stored change the `local_log_directory` variable.

Logs will temporarily be stored in `fw_dir` on the remote machines and will be cleaned up at the end of the playbook. The default remote log dir is `/tmp/nvfw`.

The following information is collected on all hosts. To limit the hosts, use the ansible `-l` parameter (ex: `-l kube-node`).

* Current firmware
* Out of date firmware
* InfiniBand configuration
* Date
* DCGM health checks
* NVSM health checks
* MAC/IP/hostname
* Misc. basic information

## Update Firmware

This role can also be used to update the firmware on DGX nodes. To achieve this, set `update_firmware: true`. Running diagnostics and updating firmware can both be achieved in the same run. Updating firmware might require rebooting the systems (depending on what portion of the firmware is being updated).

The following playbooks encapsulate this role and can be run separately to collect diagnostics and update the firmware...

```sh
# collect diagnostic info
ansible-playbook -l slurm-node playbooks/nvidia-dgx/nvidia-dgx-diag.yml
```

```sh
# update all firmware
ansible-playbook -l slurm-node playbooks/nvidia-dgx/nvidia-dgx-fw-update.yml
```

> Note: This playbook is designed to only allow upgrading of a single component per run; the recommended best-practice is to run `update_fw all`, however when updating individual components it is best to perform some level of manual verification over the logs.

> Note: It is not a requirement, but to resolve any potential issues while staff are on-site it is recommended to reboot all DGX Nodes after extensive firmware and software updates.
