Installing NVIDIA Datacenter GPU Manager
========================================

[NVIDIA Datacenter GPU Manager](https://developer.nvidia.com/dcgm) is a suite of tools for managing and monitoring NVIDIA GPUs in cluster environments.
It includes active health monitoring, comprehensive diagnostics, system alerts and governance policies including power and clock management.
It can be used standalone by system administrators and easily integrates into cluster management, resource scheduling and monitoring products from NVIDIA partners.

DCGM is included by default for NVIDIA DGX, but must be explicitly downloaded and installed for other systems.
To download DCGM, you must first register for the NVIDIA developer program,
after which you should be able to download DCGM from the [NVIDIA developer portal](https://developer.nvidia.com/dcgm).
DCGM can be downloaded as either an RPM package, for Red Hat and compatible systems; or as a DEB package, for Ubuntu.

Once DCGM has been downloaded, you can install it using DeepOps via the [nvidia-dcgm](../../playbooks/nvidia-software/nvidia-dcgm.yml) playbook.

1. Download the DCGM package and place it on your Ansible control node.
1. In your DeepOps configuration, set either the `dcgm_deb_package` or `dcgm_rpm_package` variable to the file path of the DCGM package.
1. Either run the `playbooks/nvidia-software/nvidia-dcgm.yml` playbook directly, or run the `slurm-cluster.yml` playbook with `install_dcgm: true`.
