OS provisioning via PXE
=======================

Deploying bare-metal clusters at scale generally involves some method for installing the operating system over the network.
This is typically using the [Preboot eXecution Environment (PXE)](https://en.wikipedia.org/wiki/Preboot_Execution_Environment),
a standardized environment which boots an OS from the network.

There are a wide variety of tools for managing OS installation over the network.
Most of the playbooks in DeepOps are agnostic to the OS install tooling, assuming that an OS is already present.
For example, DeepOps can be used to deploy a [Slurm cluster](../slurm-cluster/) or a [Kubernetes cluster](../k8s-cluster) regardless of how the OS was installed.
This makes it relatively easy to integrate with an existing datacenter environment.

However, DeepOps does provide tooling for several PXE installation mechanisms which can be used if an existing tool isn't already deployed.
These include:

* [MAAS](./maas.md), an open-source bare-metal provisioning tool developed by [Canonical](https://canonical.com/)
* [DGXIE](./dgxie-container.md), a containerized deployment tool developed specifically to deploy NVIDIA DGX OS
    * [DGXIE on Kubernetes](./dgxie-on-k8s.md)
* A minimal [PXE container](./minimal-pxe-container.md) which wraps [Pixiecore](https://github.com/danderson/netboot/tree/master/pixiecore), an open source tool for network booting
