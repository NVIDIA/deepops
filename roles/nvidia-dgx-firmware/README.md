# nvidia-dgx-firmware role

This role makes use of the NVIDIA DGX firmware container and can be used to:
1. Collect health & configuration diagnostics
2. Update the firmware

## Setup

1) Download the latest DGX firmware container and put it in `src/containers/dgx-firmware`. Keep the original file name. Update the role variables to reflect the version being used. 

```yml
# The Docker repo name
firmware_update_repo: nvfw-dgx1

# The Docker tag
firmware_update_tag: 19.10.7
```

2) Change the `nv_mgmt_interface` variable to reflect the systems being collected from.

```yml
# The OS/mgmt interface on the server
nv_mgmt_interface: enp1s0f0 # DGX-1
# nv_mgmt_interface: enp134s0f0 # DGX-2
# nv_mgmt_interface: enp2s0f1 # DGX-Station
```

## Collect Diagnostics

This role can be used to collect health and configuration information across a cluster. This is useful in verifying the health of a cluster or to debug a known issue. Because this is a debugging tool Ansible will continue executing tasks on all hosts even if some of the tasks fail.

Although this role is meant to be executed against a homogeneous cluster of DGX systems (all DGX-1 or all DGX-2), the majority of the functionality will be effective on any GPU cluster.

### Running

The default behavior is to collect diagnostics. To disable, change the `run_diagnostics` variable...

```yml
run_diagnostics: false
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
