Deploying the NGC-Ready playbook offline
========================================

## Necessary software mirrors

Deploying the NGC-Ready playbook assumes that several package repositories and individual software packages are available to install.
In order to deploy this configuration without Internet access, you will need to have the following software available in offline mirrors.


### Ubuntu

Apt repositories (how to mirror):


Container images (how to mirror):


HTTP downloads (how to mirror):



### Enterprise Linux

RPM repositories (how to mirror):


Container images (how to mirror):


HTTP downloads (how to mirror):



## Configuring DeepOps

To deploy the NGC-Ready playbook using alternative mirrors, you will need to configure the following items.

1. Configure the nodes to use your mirrors for the Linux distribution package repositories
1. Set the following DeepOps variables to configure other package repositories
1. Set the following DeepOps variables to configure container image pulls
1. Set the following DeepOps variables to configure HTTP downloads

