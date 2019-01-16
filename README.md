DeepOps
===

Deploy a scalable DGX cluster on-prem or in the cloud

## Contents

* [Overview](#overview)
* [Prerequisites](#prerequisites)
  * [Hardware Requirements](#hardware-requirements)
  * [Software Requirements](#software-requirements)
  * [Network Requirements](#network-requirements)
* [Installation Steps](#installation-steps)
  * [Overview](#installation-overview)
  * [1. Download/Configure](#1-download-and-configure)
  * [2. Management Server Setup](#2-management-server-setup)
  * [3. Services bootstrap](#3-services)
  * [4. DGX Setup](#4-DGX-compute-nodes)
  * [5. Login Server](#5-login-server)
  * [6, Additional Components](#6-additional-components)
* [Cluster Usage](#cluster-usage)
  * [Maintenance](#maintenance)
    * [Login Server](#login-server)
    * [Cluster-wide](#cluster-wide)
  * [Kubernetes](#kubernetes)
* [Troubleshooting](#troubleshooting)
* [Open Source Software](#open-source-software)
* [Copyright and License](#copyright-and-license)
* [Issues and Contributing](#issues-and-contributing)

## Overview

The DeepOps project aims to facilitate deployment of multi-node GPU clusters for
Deep Learning and HPC environments, in an on-prem, optionally air-gapped
datacenter or in the cloud.

This document is written as a step-by-step guide which should allow for a person with
minimal Linux system administration experience to install and configure an entire cluster
from scratch. More experienced administrators should be able to pick and choose items that
may be useful, it is not required to follow all steps in the guide if existing software or
infrastructure is to be used.

Installation involves first bootstraping management server(s) with a Kubernetes installation
and persistent volume storage using Ceph. Cluster services for provisioning operating
systems, monitoring, and mirroring container and package repos are then deployed
on Kubernetes. From there, DGX servers are booted and installed with the DGX base OS,
and Kubernetes is extended across the entire cluster to facilitate job management.
An optional login server can be used to allow users a place to interact with data locally
and launch jobs. The Slurm job scheduler can also be installed in parallel with Kubernetes
to facilitate easier large-scale training jobs or more traditional HPC workloads.

For more information on deploying DGX in the datacenter, consult the
[DGX Data Center Reference Design Whitepaper](https://nvidia-gpugenius.highspot.com/viewer/5b33fecf1279587c07d8ac86)

## Prerequisites

### Hardware Requirements

* 1 or more CPU-only servers for management
  * 3 or more servers can be used for high-availability
  * Minimum: 4 CPU cores, 16GB RAM, 100GB hard disk
    * More storage required if storing containers in registry, etc.
    * More RAM required if running more services on kubernetes or using one/few servers
  * Ubuntu 16.04 LTS installed
* 1 or more DGX compute nodes
* Laptop or workstation for provisioning/deployment
* (optional) 1 CPU-only server for user job launch, data management, etc.

### Software Requirements

The administrator's provisioning system should have the following installed:

* Ansible 2.5 or later
* git
* docker (to build containers)
* ipmitool
* python-netaddr (for kubespray)

The management server(s) should be pre-installed with Ubuntu 16.04 LTS before
starting the installation steps. If you already have a bare-metal provisioning system,
it can be used to install Ubuntu on the management server(s). Integrating the DGX Base OS
with other bare-metal provisioning systems is outside the scope of this project.

### Network Requirements

The DeepOps service container "DGXie" provides DHCP, DNS, and PXE services to the cluster,
and will allow you to automatically install the official DGX base OS on DGX servers.
If you elect to use this management service, you will need to have a dedicated network
segment and subnet which can be controlled by the DHCP server.

## Installation Steps

### Installation Overview

1. Download and configure DeepOps repo
2. Deploy management server(s)
   * Bootstrap
   * Deploy Kubernetes
   * Deploy Ceph persistent storage on management nodes
3. Deploy cluster service containers on Kubernetes
   * DHCP/DNS/PXE, container registry, Apt repo, monitoring, alerting
4. Deploy DGX-1 compute nodes
   * Install DGX OS (via PXE), bootstrap (via Ansible)
   * Update firmware (via Ansible, if required)
   * Join DGX-1 compute nodes to Kubernetes cluster and deploy GPU device plugin
5. Deploy login node
   * Install OS (via PXE), bootstrap (via Ansible)
   * Install/build HPC software and modules
6. Deploy cluster SW layers
   * Install Slurm HPC scheduler on login and compute nodes
   * Configure Kubernetes Oauth integration for user access

### 1. Download and configure

Download the DeepOps repo onto the provisioning system and copy the example configuration
files so that you can make local changes:

```sh
git clone --recursive https://github.com/NVIDIA/deepops.git
cp -r config.example/ config/
ansible-galaxy install -r requirements.yml
```

> Note: In Git 2.16.2 or later, use `--recurse-submodules` instead of `--recursive`.
> If you did a non-recursive clone, you can later run `git submodule update --init --recursive`
> to pull down submodules

The `config/` directory is ignored by git, so a new git repository can be created in this
directory to track local changes:

```sh
cd config/
git init .
git add .
git commit -am 'initial commit'
```

Use the `config/inventory` file to set the cluster server hostnames, and optional
per-host info like IP addresses and network interfaces. The cluster should
ideally use DNS, but you can also explicitly set server IP addresses in the
inventory file.

Optional inventory settings:

* Use the `ansible_host` variable to set alternate IP addresses for servers or for
servers which do not have resolvable hostnames
* Use the `ib_bond_addr` variable to configure the infiniband network adapters
with IPoIB in a single bonded interface

Configure cluster parameters by modifying the various yaml files in the `config/group_vars`
directory. The cluster-wide global config resides in the `all.yml` file, while
group-specific options reside in the other files. File names correspond to groups
in the inventory file, i.e. `[dgx-servers]` in the inventory file corresponds with
`config/group_vars/dgx-servers.yml`.

### 2. Management server setup

The configuration assumes a single cpu-only management server,
but multiple management servers can be used for high-availability.

Install the latest version of Ubuntu Server 16.04 LTS on each management server.
Be sure to enable SSH and record the user and password used during install.

__Bootstrap:__

The password and SSH keys added to the `ubuntu` user in the `config/group_vars/all.yml`
file will be configured on the management node. You should add an SSH key to the configuration
file, or you will have to append the `-k` flag and type the password for the `ubuntu`
user for all Ansible commands following the bootstrap.

Deploy management node(s):

> Type the password for the user you configured during management server OS
installation when prompted to allow for the use of `sudo` when configuring the
management servers. If the management servers were installed with the use of
SSH keys and sudo does not require a password, you may omit the `-k` and `-K`
flags

```sh
ansible-playbook -l mgmt -k -K ansible/playbooks/bootstrap.yml
```

Where `mgmt` is the group of servers in your `config/inventory` file which will become
management servers for the cluster.

To run arbitrary commands in parallel across nodes in the cluster, you can use ansible
and the groups or hosts defined in the inventory file, for example:

```sh
ansible mgmt -a hostname
```

> For more info, see: https://docs.ansible.com/ansible/latest/user_guide/intro_adhoc.html

Apply additional changes to management servers to disable swap (required for Kubernetes):

```sh
ansible mgmt -b -a "swapoff -a"
```

If you need to configure a secondary network interface for the private DGX network,
modify `/etc/network/interfaces`. For example:

```sh
auto ens192
    iface ens192 inet static
    address 192.168.1.1/24
    dns-nameservers 8.8.8.8 8.8.4.4
    gateway 192.168.1.1
    mtu 1500
```

__Kubernetes:__

Deploy Kubernetes on management servers:

Modify the file `config/kube.yml` if needed and deploy Kubernetes:

```sh
ansible-playbook -l mgmt -v -b --flush-cache --extra-vars "@config/kube.yml" kubespray/cluster.yml
```
<!--
Place a hold on the `docker-ce` package so it doesn't get upgraded:

```sh
ansible mgmt -b -a "apt-mark hold docker-ce"
```
-->

Set up Kubernetes for remote administration:

```sh
ansible mgmt -b -m fetch -a "src=/etc/kubernetes/admin.conf flat=yes dest=./"
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
```

To make administration easier, you may want to copy the `kubectl` binary to someplace in your `$PATH`
and copy the `admin.conf` configuration file to `~/.kube/config` so that it is used by default.
Otherwise, you may use the `kubectl` flag `--kubeconfig=./admin.conf` instead of copying the configuration file.

If you have an existing Kubernetes configuration file, you can merge the two with:

```sh
mv ~/.kube/config{,.bak} && KUBECONFIG=./admin.conf:~/.kube/config.bak kubectl config view --flatten | tee ~/.kube/config
```

Test you can access the kubernetes cluster:

```sh
$ kubectl get nodes
NAME      STATUS    ROLES         AGE       VERSION
mgmt01    Ready     master,node   7m        v1.11.0
```

__Helm:__

Some services are installed using [Helm](https://helm.sh/), a package manager for Kubernetes.

Install the Helm client by following the instructions for the OS on your provisioning system: https://docs.helm.sh/using_helm/#installing-helm

If you're using Linux, the script `scripts/helm_install_linux.sh` will set up Helm for the current user

Be sure to install a version of Helm matching the version in `config/kube.yml`

(Optional) If `helm_enabled` is `true` in `config/kube.yml`,
the Helm server will already be deployed in Kubernetes.
If it needs to be installed manually for some reason, run:

```sh
kubectl create sa tiller --namespace kube-system
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller --node-selectors node-role.kubernetes.io/master=true
```

__Ceph:__

Persistent storage for Kubernetes on the management nodes is supplied by Ceph.
Ceph is provisioned using Rook to simplify deployment:

```sh
helm repo add rook-master https://charts.rook.io/master
helm install --namespace rook-ceph-system --name rook-ceph rook-master/rook-ceph --version v0.7.0-284.g863c10f --set agent.flexVolumeDirPath=/var/lib/kubelet/volume-plugins/
kubectl create -f services/rook-cluster.yml
```

> Note: It will take a few minutes for containers to be pulled and started.
> Wait for Rook to be fully installed before proceeding

You can check Ceph status with:

```sh
kubectl -n rook-ceph exec -ti rook-ceph-tools ceph status
```
<!--
Once the Ceph filesystem is up, it is safe to continue, i.e:

```sh
$ kubectl -n rook-ceph exec -ti rook-ceph-tools ceph status | grep mds
    mds: cephfs-1/1/1 up  {0=cephfs-54949bc7c4-8jv4t=up:active}, 1 up:standby-replay
```
-->

### 3. Services

#### __Ingress controller:__

An ingress controller routes external traffic to services.

Modify `config/ingress.yml` if needed and install the ingress controller:

```sh
helm install --values config/ingress.yml stable/nginx-ingress
```

You can check the ingress controller logs with:

```sh
kubectl logs -l app=nginx-ingress
```

#### __DHCP/DNS/PXE server (DGXie):__

DGXie is an all-in-one container for DHCP, DNS, and PXE, specifically tailored to the DGX Base OS.
If you already have DHCP, DNS, or PXE servers you can skip this step.

__Setup__

You will need to download the official DGX Base OS ISO image to your provisioning machine.
The latest DGX Base OS is available via the NVIDIA Entperprise Support Portal (ESP).

Copy the DGX Base OS ISO to shared storage via a container running in Kubernetes,
substituting the path to the DGX ISO you downloaded (be sure to wait for the `iso-loader` POD
to be in the *Running* state before attempting to copy the ISO):

```sh
kubectl apply -f services/iso-loader.yml
kubectl cp /path/to/DGXServer-3.1.2.170902_f8777e.iso $(kubectl get pod -l app=iso-loader -o custom-columns=:metadata.name --no-headers):/data/iso/
```

> Note: If the `iso-loader` POD fails to mount the CephFS volume, you may need to restart the kubelet service on the master node(s): `ansible mgmt -b -a "systemctl restart kubelet"`
> You may see an error that looks like this in your syslog file: `failed to get Plugin from volumeSpec for volume "cephfs" err=no volume plugin matched`

__Configure__

Modify the DGXie configuration in `config/dgxie.yml` to set values for the DHCP server
and DGX install process

Modify `config/dhcpd.hosts.conf` to add a static IP lease for each login node and DGX
server in the cluster if required. IP addresses should match those used in the `config/inventory` file.
You may also add other valid configuration options for dnsmasq to this file.

You can get the MAC address of DGX system interfaces via the BMC, for example:

```sh
# interface 1
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> raw 0x30 0x19 0x00 0x02 | tail -c 18 | tr ' ' ':'
# interface 2
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> raw 0x30 0x19 0x00 0x12 | tail -c 18 | tr ' ' ':'
```

Modify `config/machines.json` to add a PXE entry for each DGX. Copy the `dgx-example` section and modify
the MAC address for each DGX you would like to boot. You can modify boot parameters or install
alternate operating systems if required.

Store the config files as config-maps in Kubernetes, even if you have not
made any changes (the DGXie container will try to mount these config maps):

```sh
kubectl create configmap dhcpd --from-file=config/dhcpd.hosts.conf
kubectl create configmap pxe-machines --from-file=config/machines.json
```

__Deploy DGXie service__

Launch the DGXie service:

```sh
helm install --values config/dgxie.yml services/dgxie
```

Check the DGXie logs to make sure the services were started without errors:

```sh
kubectl logs -l app=dgxie
```

Configure the management server(s) to use DGXie for cluster-wide DNS:

```sh
ansible-playbook -l mgmt ansible/playbooks/resolv.yml
```

If you later make changes to `config/dhcpd.hosts.conf`, you can update the file in Kubernetes
and restart the service with:

```sh
kubectl create configmap dhcpd --from-file=config/dhcpd.hosts.conf -o yaml --dry-run | kubectl replace -f -
kubectl delete pod -l app=dgxie
```

If you make changes to `machines.json`, you can update the file without having to restart the DGXie POD:

```sh
kubectl create configmap pxe-machines --from-file=config/machines.json -o yaml --dry-run | kubectl replace -f -
```

#### __APT Repo:__

Launch service. Runs on port `30000`: http://mgmt:30000

```sh
kubectl apply -f services/apt.yml
```

#### __Container Registry:__

Modify `config/registry.yml` if needed and launch the container registry:

```sh
helm repo add stable https://kubernetes-charts.storage.googleapis.com
helm install --values config/registry.yml stable/docker-registry --version 1.4.3
```

Once you have [provisioned DGX servers](#4-DGX-compute-nodes),
configure them to allow access to the local (insecure) container registry:

```sh
ansible-playbook -k ansible/playbooks/docker.yml
```

You can check the container registry logs with:

```sh
kubectl logs -l app=docker-registry
```

The container registry will be available to nodes in the cluster at `registry.local`, for example:

```sh
# pull container image from docker hub
docker pull busybox:latest

# tag image for local container registry
# (you can also get the image ID manually with: docker images)
docker tag $(docker images -f reference=busybox --format "{{.ID}}") registry.local/busybox

# push image to local container registry
docker push registry.local/busybox
```

#### __Monitoring:__

Cluster monitoring is provided by Prometheus and Grafana

Service addresses:

* Grafana: http://mgmt:30200
* Prometheus: http://mgmt:30500
* Alertmanager: http://mgmt:30400

Where `mgmt` represents a DNS name or IP address of one of the management hosts in the kubernetes cluster.
The default login for Grafana is `admin` for the username and password.

Modify `config/prometheus-operator.yml` and `config/kube-prometheus.yml` if desired and deploy the monitoring
and alerting stack:

```sh
helm repo add coreos https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/
helm install coreos/prometheus-operator --name prometheus-operator --namespace monitoring --values config/prometheus-operator.yml
kubectl create configmap kube-prometheus-grafana-gpu --from-file=config/gpu-dashboard.json -n monitoring
helm install coreos/kube-prometheus --name kube-prometheus --namespace monitoring --values config/kube-prometheus.yml
```

To collect GPU metrics, label each GPU node and deploy the DCGM Prometheus exporter:

```sh
kubectl label nodes <gpu-node-name> hardware-type=NVIDIAGPU
kubectl create -f services/dcgm-exporter.yml
```
<!--
Enable the Ceph prometheus exporter:

```sh
kubectl -n rook-ceph exec -ti rook-ceph-tools ceph mgr module enable prometheus
```
-->

#### __Logging:__

Centralized logging is provided by Filebeat, Elasticsearch and Kibana

> Note: The ELK Helm chart is current out of date and does not provide support for
> setting the Kibana NodePort

*todo:*
  * filebeat syslog module needs to be in UTC somehow, syslog in UTC?
  * fix kibana nodeport issue

Make sure all systems are set to the same timezone:

```sh
ansible all -k -b -a 'timedatectl status'
```

To update, use: `ansible <hostname> -k -b -a 'timedatectl set-timezone <timezone>'

Install [Osquery](https://osquery.io/):

```sh
ansible-playbook -k ansible/playbooks/osquery.yml
```

Deploy Elasticsearch and Kibana:

```sh
helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
helm install --name elk --namespace logging --values config/elk.yml incubator/elastic-stack
```

The ELK stack will take several minutes to install,
wait for elasticsearch to be ready in Kibana before proceeding.

Launch Filebeat, which will create an Elasticsearch index automatically:

```sh
helm install --name log --namespace logging --values config/filebeat.yml stable/filebeat
```

The logging stack can be deleted with:

```sh
helm del --purge log
helm del --purge elk
kubectl delete statefulset/elk-elasticsearch-data
kubectl delete pvc -l app=elasticsearch
# wait for all statefulsets to be removed before re-installing...
```

### 4. DGX compute nodes:

__Provisioning:__

Provision DGX nodes with the official DGX ISO over PXE boot using DGXie.

> Note: The `scripts/do_ipmi.sh` script has these commands and can be looped over multiple hosts

Disable the DGX IPMI boot device selection 60s timeout, you only need to do this once for
each DGX, but it is required:

```sh
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> raw 0x00 0x08 0x03 0x08
```

> Note: The default IPMI username and password is `qct.admin`

Set the DGX to boot from the first disk, using EFI, and to persist the setting:

```sh
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> raw 0x00 0x08 0x05 0xe0 0x08 0x00 0x00 0x00
```

Set the DGX to boot from the network in EFI mode, for the next boot only. If you set the DGX
to always boot from the network, they will get stuck in an install loop.
The installer should set the system to boot to the first disk via EFI after the install is finished

```sh
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> chassis bootdev pxe options=efiboot
```

> Note: If you have manually modified the boot order in the DGX SBIOS, you may need to manually return
> it to boot from disk by default before running the IPMI commands above to alter the boot order

Power cycle/on the DGX to begin the install process

```sh
ipmitool -I lanplus -U <username> -P <password> -H <DGX BMC IP> power cycle
```

The DGX install process will take approximately 15 minutes. You can check the DGXie logs with:

```sh
kubectl logs -l app=dgxie
```

If your DGX are on an un-routable subnet, uncomment the `ansible_ssh_common_args` variable in the
`config/group_vars/dgx-servers.yml` file and modify the IP address to the IP address of the management server
with access to the private subnet, i.e.

```sh
ansible_ssh_common_args: '-o ProxyCommand="ssh -W %h:%p -q ubuntu@10.0.0.1"'
```

Test the connection to the DGX servers via the bastion host (management server). Type the password
for `dgxuser` on the DGX when prompted. The default password for `dgxuser` is `DgxUser123`:

```sh
ansible dgx-servers -k -a 'hostname'
```

__Configuration:__

Configuration of the DGX is accomplished via Ansible roles.
Various playbooks to install components are available in `ansible/playbooks`.
Modify the file `ansible/site.yml` to enable or disable various playbooks, or run playbooks
directly.

Type the default password for `dgxuser` on the DGX when prompted while running the bootstrap playbook.
The default password for `dgxuser` is `DgxUser123`:

```sh
ansible-playbook -k -K -l dgx-servers ansible/playbooks/bootstrap.yml
```

After running the first command, you may omit the `-K` flag on subsequent runs. The password
for the `deepops` user will also change to the one set in the `groups_vars/all.yml` file
(by default, this password is `deepops`). Run the site playbook to finish configuring the DGX:

```sh
ansible-playbook -k -l dgx-servers ansible/site.yml
```

<!--
Once the DGX has been configured, re-run the Ansible playbook to generate an `/etc/hosts`
file.

> You may need to comment out any nodes in the inventory file that are not reachable
by Ansible if you receive an error like: "'dict object' has no attribute 'ansible_default_ipv4'"

```sh
ansible-playbook -k -l all ansible/playbooks/hosts.yml
```
-->

__Adding DGX to Kubernetes:__

Create the NVIDIA GPU k8s device plugin daemon set (just need to do this once):

```sh
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v1.11/nvidia-device-plugin.yml
```

If the DGX is a member of the Slurm cluster, be sure to drain node in Slurm so that it does
not accept Slurm jobs. From the login node, run:

```sh
sudo scontrol update node=dgx01 state=drain reason=k8s
```

Modify the `config/inventory` file to add the DGX to the `kube-node` and `k8s-gpu` categories by uncommenting
the `dgx-servers` entry in these sections

Re-run Kubespray to install Kubernetes on the DGX:

```sh
ansible-playbook -l k8s-cluster -k -v -b --flush-cache --extra-vars "@config/kube.yml" kubespray/cluster.yml
```

> Note: If the kubesray run fails for any reason, try running again

Check that the installation was successful:

```sh
$ kubectl get nodes
NAME      STATUS    ROLES         AGE       VERSION
dgx01     Ready     node          3m        v1.11.0
mgmt01    Ready     master,node   2d        v1.11.0
```

Place a hold on the `docker-ce` package so it doesn't get upgraded:

```sh
ansible dgx-servers -k -b -a "apt-mark hold docker-ce"
```

Install the nvidia-container-runtime on the DGX:

```sh
ansible-playbook -l k8s-gpu -k -v -b --flush-cache --extra-vars "@config/kube.yml" playbooks/k8s-gpu.yml
```

Test that GPU support is working:

```sh
kubectl apply -f tests/gpu-test-job.yml
kubectl exec -ti gpu-pod -- nvidia-smi -L
kubectl delete pod gpu-pod
```

### 5. Login server:

> Note: If you do not require a login node, you may skip this section

> Note: By default the login node(s) are not part of the kubernetes cluster. If you need to
add login node(s) to the kubernetes cluster, add login servers to the kubernetes categories
in the `config/inventory` file and re-run the ansible playbooks as above for management and
DGX servers.

__Provisioning:__

Modify `config/dhcpd.hosts.conf` to add a static IP lease for each login node
if required. IP addresses should match those used in the `config/inventory` file.

Update the `dhcpd.hosts.conf` config map if modified and restart the DGXie POD:

```sh
kubectl create configmap dhcpd --from-file=config/dhcpd.hosts.conf -o yaml --dry-run | kubectl replace -f -
kubectl delete pod -l app=dgxie
```

Modify `config/machines.json` to add a PXE entry for each login node.
Copy the `64-bit-ubuntu-example` section and modify
the MAC address for each login node you would like to boot. You can modify boot parameters or install
alternate operating systems if required.

Update the PXE server config map:

```sh
kubectl create configmap pxe-machines --from-file=config/machines.json -o yaml --dry-run | kubectl replace -f -
```

Set login nodes to boot from the network for the next boot only and power on the systems.
The login nodes should receive a response from the DGXie service and begin the OS install process.

> Note: Be sure to either monitor the PXE install or configure servers to boot from the network
on the next boot only to avoid a re-install loop

If manually configuring the install, be sure the initial user matches the user in `config/group_vars/login.yml`.

__Configuration:__

Once OS installation is complete, bootstrap and configure the login node(s) via Ansible.

If your login nodes are on an un-routable subnet, uncomment the `ansible_ssh_common_args` variable in the
`config/group_vars/login.yml` file and modify the IP address to the IP address of the management server
with access to the private subnet, i.e.

```sh
ansible_ssh_common_args: '-o ProxyCommand="ssh -W %h:%p -q ubuntu@10.0.0.1"'
```

Various playbooks to install components are available in `ansible/playbooks`.
Modify the file `ansible/site.yml` to enable or disable various playbooks, or run playbooks
directly:

```sh
ansible-playbook -k -K -l login ansible/playbooks/bootstrap.yml
ansible-playbook -k -l login ansible/site.yml
```

### 6. Additional Components

#### __Slurm:__

Slurm overview: https://slurm.schedmd.com/overview.html

"Slurm is an open source, fault-tolerant, and highly scalable cluster management and job scheduling system for large and small Linux clusters."

> Note: For more information on Slurm and GPUs, see: https://github.com/dholt/slurm-gpu

To install Slurm, configure nodes in `config/inventory` and run the Ansible playbook:

```sh
ansible-playbook -k -l slurm-cluster ansible/playbooks/slurm.yml
```

DGX nodes may appear 'down' in Slurm after install due to rebooting. Set nodes to idle if required:

```sh
sudo scontrol update node=dgx01 state=idle
```

## Cluster Usage

### Maintenance

__Updating Firmware:__

Firmware on the DGX can be updated through the firmware update container(s) and Ansible.

1. Download the firmware update container package from the NVIDIA Enterprise Support Portal.
Updates are published as announcements on the support portal (example: https://goo.gl/3zimCk).
Make sure you download the correct package depending on the GPU in the DGX-1:
   - For V100 (Volta), download the '0102' package - for example: https://dgxdownloads.nvidia.com/custhelp/dgx1/NVIDIA_Containers/nvidia-dgx-fw-0102-20180424.tar.gz
   - For P100 (Pascal), download the '0101' package - for example: https://dgxdownloads.nvidia.com/custhelp/dgx1/NVIDIA_Containers/nvidia-dgx-fw-0101-20180424.tar.gz
2. Once you've download the `.tar.gz` file, copy or move it inside `containers/dgx-firmware`
3. Edit the value of `firmware_update_container` in the file `ansible/roles/nvidia-dgx-firmware/vars/main.yml` to match
the name of the downloaded firmware container.
4. Run the Ansible playbook to update DGX firmware:

```sh
ansible-playbook -k -l dgx-servers ansible/playbooks/firmware.yml
```

#### Login server

__Adding Software:__

To modify installed software on cluster nodes, edit the package list in `ansible/roles/software/defaults/main.yml`
and apply the changes:

```sh
ansible-playbook -k -l login ansible/playbooks/software.yml
```

The `playbooks/extra.yml` file contains optional configuration (these will be moved at a later date):

```sh
ansible-playbook -k -l all playbooks/extra.yml
```

__Building software__:

HPC clusters generally utilize a system of versioned software modules instead of installing
software via the OS package manager. These software builds can be made easier with the EasyBuild tool.
The software build environment should be set up on the login node in a shared directory accessible
by all cluster nodes.

Assuming you created or used an existing NFS share during cluster bootstrap, create a directory
to hold software builds and create a `direnv` file to facilitate easier EasyBuild builds:

EasyBuild environment file:
 
```sh
$ cat /shared/.envrc
export EASYBUILD_PREFIX=/shared/sw
export EASYBUILD_MODULES_TOOL=Lmod
export EASYBUILD_JOB_BACKEND=GC3Pie
export EASYBUILD_JOB_BACKEND_CONFIG=/shared/.gc3pie.cfg
module use /shared/sw/modules/all
module load EasyBuild
```

Where the shared NFS directory is `/shared`, and initial software/modules built with EasyBuild are
installed in `/shared/sw`.

The `direnv` package should have been installed by default during cluster node configuration.
For more information on `direnv`, see: https://direnv.net/.

Use `direnv` to automatically set your EasyBuild environment; first
add an appropriate command to your shell login scripts:

```sh
type direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"
```

Then `cd /shared` and run `direnv allow`. The `.envrc` file should set up the environment to use EasyBuild

Install [EasyBuild](https://easybuilders.github.io/easybuild/) using the shared directory as the install path:

```sh
# pick an installation prefix to install EasyBuild to (change this to your liking)
EASYBUILD_PREFIX=/shared/sw

# download script
curl -O https://raw.githubusercontent.com/easybuilders/easybuild-framework/develop/easybuild/scripts/bootstrap_eb.py

# bootstrap EasyBuild
python bootstrap_eb.py $EASYBUILD_PREFIX

# update $MODULEPATH, and load the EasyBuild module
module use $EASYBUILD_PREFIX/modules/all
module load EasyBuild
```

Example usage for building software:

```sh
# search
eb -S gcc-6
# build
eb GCC-6.4.0-2.28.eb -r
```

Example usage for using software:

```sh
# prepend environment module path
export MODULEPATH=$EASYBUILD_PREFIX/modules/all:$MODULEPATH

# load environment module
module load HPL
```

#### Cluster-wide

__Slurm updates:__

```sh
# whole shebang:
ansible-playbook -k -l slurm-cluster ansible/playbooks/slurm.yml
# just prolog and/or epilog:
ansible-playbook -k -l compute-nodes --tags prolog,epilog -e 'gather_facts=no' ansible/playbooks/slurm.yml
```

__Modify GPU drivers:__

```sh
ansible-playbook -k -l <dgx-hostname> playbooks/gpu-driver.yml
```

__Extra:__

Set up `/raid` RAID-0 array cache (can also add `rebuild-raid` to PXE boot cmdline when installing):

```sh
ansible dgx-servers -k -b -a "/usr/bin/configure_raid_array.py -i"
```

Un-freeze NVLINK counters (may want to use `0brw` for just read/write):

```sh
ansible dgx-servers -k -b -a "nvidia-smi nvlink -sc 0bz"
```

### Kubernetes

__Managing DGX scheduler allocation:__

Once the DGX compute nodes have been added to Kubernetes and Slurm, you can use the `scripts/doctl.sh`
script to manage which scheduler each DGX is allowed to run jobs from.

__NVIDIA GPU Cloud Container Registry (NGC):__

Create secret for registry login:

```sh
kubectl create secret docker-registry ngc --docker-server=nvcr.io --docker-username='$oauthtoken' --docker-password=<api-key> --docker-email='foo@example.com'
```

Add to Kubernetes pod spec:

```sh
  imagePullSecrets:
    - name: ngc
```

__Upgrading Helm Charts:__

If you make changes to configuration or want to update Helm charts, you can use the `helm upgrade`
command to apply changes

Show currently installed releases:

```sh
helm list
```

To upgrade the ingress controller with new values from `config/ingress.yml` for example, you would run:

```sh
helm upgrade --values config/ingress.yml <release_name> stable/nginx-ingress
```

Where `<release_name>` is the name of the deployed ingress controller chart obtained from
`helm list`.

#### __Kubernetes user access:__

__TODO__:

* (done) restrict namespace to nodes with specific labels, i.e. `scheduler=k8s`
* wait for k8s fix to daemonset and PodNodeSelector issues

__Using OAuth2__

References: https://medium.com/@jessgreb01/kubernetes-authn-authz-with-google-oidc-and-rbac-74509ca8267e

Copy `admin.conf` and `ca.pem` from a kube master (i.e. `mgmt01`) to `/root/.kube` on the login
node (i.e. `login01`).

Generate an OAUTH2 client JSON config file and copy the user script to the login node:

```sh
sudo mkdir -p /shared/{bin,etc}
sudo cp scripts/k8s_user.sh /shared/bin/
sudo chmod +x /shared/bin/k8s_user.sh
sudo cp config/google_oauth2_client.json /shared/etc/
```

Download `kubectl` and `ks` (ksonnet) and put in `/shared/bin`

Users can run the script to log in to Google Auth, generate tokens and create a kube config:
`sudo /shared/bin/k8s_user.sh`

__Restrict Namespaces:__

> todo: a daemonset will still continuously try and fail to schedule pods on all nodes

User namespaces need to be restricted to nodes which are in k8s scheduling mode.
Otherwise users can run pods on management nodes and nodes which are being
managed by Slurm (via a DaemonSet for example).

Update the Kubespray config in `config/kube.yml` to tell the Kube API server to use the `PodNodeSelector`
admission controller (this should already be the default):

```sh
kube_apiserver_admission_control:
  ...
  - PodNodeSelector
```

Patch namespaces to apply a specific node selector to every pod:

```sh
kubectl patch namespace <username> -p '{"metadata":{"annotations":{"scheduler.alpha.kubernetes.io/node-selector":"scheduler=k8s"}}}'
kubectl get ns <username> -o yaml
```

Where `<username>` is the name of the namespace, typically the same as the username

__Using certs__

Source: https://docs.bitnami.com/kubernetes/how-to/configure-rbac-in-your-kubernetes-cluster/

Copy the script to one of the management nodes and run to create a user:

```sh
scp scripts/add_user.sh mgmt-01:/tmp
ssh mgmt-01 /tmp/add_user.sh <username>
scp mgmt-01:~/<username>.kubeconfig ~/.kube/config
```

Where `<username>` is the name of the new user account being created

#### __Kubernetes add-ons:__

__Service Mesh:__

> This may be needed for L7 load-balancing for GRPC services

```sh
kubectl apply -f services/ambassador-service.yml
kubectl apply -f services/ambassador-rbac.yml
```

<!--
__DHCP/PXE (pixiecore):__

> old method with pixiecore and dhcp server. uefi boot doesn't respond to proxyDHCP so this doesn't work

```sh
kubectl create configmap pxe --from-file=config/machines.json
kubectl apply -f services/dhcpd.yml
kubectl apply -f services/pxe.yml
```
-->
<!--
__jupyterhub:__

> deployment working (with intermitten RBAC success); not respecting custom config

> Currently the Helm chart does not support custom resource limits so the POD has access to all GPUs on the system

All nodes which will use persistent storage need the `rbd` binary (mgmt nodes in ceph cluster already have it): `apt install ceph-common`

Label nodes where you want the notebook pods to run: `kubectl label nodes prm-dgx-05 gpu=true`

Modify `config/jupyterhub-config.yml` if needed

```sh
kubectl create ns jh
# run this next one from a mgmt node
kubectl create secret generic ceph-client --type="kubernetes.io/rbd" --from-literal=key="$(sudo ceph auth get-key client.kube)" --namespace=jh
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update
helm install jupyterhub/jupyterhub --name=jupyterhub --namespace=jh -f config/jupyterhub-config.yaml --set prePuller.enabled=false
```

Remove:

```sh
helm del --purge jupyterhub
```

You may have to install/delete/re-install if there are RBAC errors. You can also try deleting the proxy pod so it's re-created

If you make changes to the config file:

```sh
helm upgrade jupyterhub jupyterhub/jupyterhub --version=v0.6 -f config/jupyterhub-config.yaml
```
-->

## Troubleshooting

If Ansible complains that a variable is undefined, you can check node values with something like:

```sh
ansible all -m debug -a "var=ansible_default_ipv4"
```

Where `ansible_default_ipv4` is the variable in question

__Rook:__

If you need to remove Rook for any reason, here are the steps:

```sh
kubectl delete -f services/rook-cluster.yml
helm del --purge rook-ceph
ansible mgmt -b -m file -a "path=/var/lib/rook state=absent"
```


## Open Source Software

Software used in this project:

* Ansible roles:
  * Cachefilesd: https://github.com/Ilyes512/ansible-role-cachefilesd
  * Docker: https://github.com/angstwad/docker.ubuntu
  * Kerberos: https://github.com/bennojoy/kerberos_client
  * SSH: https://github.com/weareinteractive/ansible-ssh
  * Osquery: https://github.com/apolloclark/ansible-role-osquery
* Kubespray: https://github.com/kubernetes-incubator/kubespray
* Ceph: https://github.com/ceph/ceph-ansible
* Pixiecore: https://github.com/google/netboot/tree/master/pixiecore

## Copyright and License

This project is released under the [BSD 3-clause license](https://github.com/NVIDIA/deepops/blob/master/LICENSE).

## Issues and Contributing

A signed copy of the [Contributor License Agreement](https://raw.githubusercontent.com/NVIDIA/deepops/master/CLA) needs to be provided to <a href="mailto:deepops@nvidia.com">deepops@nvidia.com</a> before any change can be accepted.

* Please let us know by [filing a new issue](https://github.com/NVIDIA/deepops/issues/new)
* You can contribute by opening a [pull request](https://help.github.com/articles/using-pull-requests/)
