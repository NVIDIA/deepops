# nvidia-dgx-diag role

This role is meant to be used to collect health and configuration information across a cluster. This can be used to verify the health of a cluster or to debug a known issue. Because this is a debugging tool Ansible will continue executing tasks on all hosts even if some of the tasks fail.

Although this role is meant to be executed against a homogeneous cluster of DGX systems (all DGX-1 or all DGX-2), the majority of the functionality will be effective on any GPU cluster.


## Setup

1) Download the latest DGX firmware container and put it in `./deepops/config/containers/dgx-firmware`. Keep the original file name. Update the role variables to reflect the version being used. 

``` sh
# The Docker repo name
firmware_update_repo: nvfw-dgx1

# The Docker tag
firmware_update_tag: 19.10.7
```

2) Change the `nv_mgmt_interface` variable to reflect the systems being collected from.


## Collected Information

All logs will be stored locally in `./deepops/config/logs`. Logs are stored by hostname with timestamps. To change where logs are stored change the `local_log_directory` variable.

Logs will temporarily be stored in `nv_diag_dir` on the remote machines and will be cleaned up at the end of the playbook. The default remote log dir is `/tmp/nv-diag`.

The following information is collected on all `kube-node` and `slurm-node` hosts:

* Current firmware
* Out of date firmware
* InfiniBand configuration
* Date
* DCGM health checks
* NVSM health checks
* MAC/IP/hostname
* Misc. basic information

