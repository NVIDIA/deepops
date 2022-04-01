Deploy NVIDIA Network Operator with DeepOps
===========================================

## Overview

NVIDIA Network Operator leverages Kubernetes CRDs and Operator SDK to manage networking related components in Kuberenets cluster. One of the key components is SR-IOV, which partitions a single PCIe hardware into multiple Virtual Functions (VFs) and attach them directly to Kubernetes pods without going through the virtualization layer on the hosts, thus enables the high performance communication between workloads. High performance networking in Kuberentes also requires a few other components, such as multus-CNI, device drivers and plugins, etc, NVIDIA network operator aims to manage all those necessary components automatically under one operator frame work to simply the deployment, operation and management of NVIDIA networking for Kubernetes.

Here are the key components that NVIDIA network operator try to deploy together:

* SR-IOV Virtual Function (VF) activation
* Multus CNI
* SR-IOV CNI for kubernetes
* SR-IOV device plugin for kubernetes
* Multus CNI
* Helm chart for NVIDIA network operator

This playbook also install the latest Kubeflow/MPI-Operator, currently version v2beta1, for multi-node MPI jobs.

Currently only InfiniBand networking is supported in this implementation, RoCE networking support will be added shortly.


## Requirements and Tested Environment:

This playbook is developed and tested in following environments:

* NVIDIA DGX servers with DGX OS 5.1
* Mellanox ConnectX-6 VPI HCA
* Ansible 2.9.27 (deployed by DeepOps)
* Kubernetes v1.21.6 (deployed by DeepOps)
* Helm version v3.6.3 (deployed by DeepOps)
* NVIDIA network opertor v1.1.0
* InfiniBand networking. (Ethernet networking support will be added in the future.)

## Deployment Steps

1. Make sure underlying InfiniBand network works properly between Kubernetes nodes. It's recommended to run some bare metal micro benchmark testing to verify the IB network is working as expected, for example, NVIDIA perftest package can be used for that purpose.

2. Enabling IB port virtualization on IB opensm. This is done in an IB switch in the lab:

   ```sh
   IB_Switch (config) # ib sm virt enable
   ```

3. Verify SR-IOV is enabled in BIOS and HCAs.

   Use following commands to verify SR-IOV and VFs are enabled on ConnectX-6 HCAs, "0000:05:00.0" is the HCA's PCIe bus number.

   ```sh
   sudo mlxconfig -d 0000:05:00.0 q | grep -i "sriov\|vfs"
   ```
4. Set up Kubernetes cluster

   Kubernetes installation is done by DeepOps Ansible playbooks, For more information on Ansible and why we use it, consult the [Ansible Guide](ANSIBLE.md).

  - Install and configure DeepOps on managemet node:

     ```sh
     git clone https://github.com/NVIDIA/deepops.git
     cd deepops/
     ./scripts/setup.sh
     vi config/inventory
     ```
    Configuring the Ansible inventory file by editing the "config/inventory" file,  and verify connectivity to all nodes.
    > NOTE: Be warned that `/etc/hostname` and `/etc/hosts` on each host will be modified to the name(s) specified in the inventory file, so it is best to use the actual names of the hosts.

    When modifying the inventory, if the hosts are not accessible from the management node by their hostname, supply an an `ansible_host` with its IP address. Example of the inventory file:

    ```yml
    # in config/inventory...
    [all]
    mgmt01     ansible_host=192.168.1.11
    gpu01      ansible_host=192.168.2.11
    gpu02      ansible_host=192.168.3.11
    ...
    [kube-master]
    mgmt01
    [kube-node]
    gpu01
    gpu02
    ```
  - Add or modify user(s) across cluster if necessary:
    The ansible scripts assume a consistent user which has access to all nodes in the cluster.
     > Note: If a user with the same username, uid, and password exists on each node, skip this step. It is critical for the user to exist with the same uid across all nodes.
    
     ```sh
     # The default user is `nvidia` with password `deepops`
     # Modify this user/password in config/group_vars/all.yaml as desired
     vi config/group_vars/all.yml
     ```

     Run the users playbook to create/modify the user across all nodes.

     ```sh
     # NOTE: If SSH requires a password, add: `-k`
     # NOTE: If sudo on remote machine requires a password, add: `-K`
     # NOTE: If SSH user is different than current user, add: `-u <user>`
     ansible-playbook -b playbooks/generic/users.yml
     ```
     Verify the configuration

     ```sh
     ansible all -m raw -a "hostname"
     ```

  - Deploying and verifying Kubernetes cluster
    Install Kubernetes using Ansible and Kubespray

    ```sh
    # NOTE: If SSH requires a password, add: `-k`
    # NOTE: If sudo on remote machine requires a password, add: `-K`
    # NOTE: If SSH user is different than current user, add: `-u ubuntu`
    ansible-playbook -l k8s-cluster playbooks/k8s-cluster.yml
    ```
    Please refer to [DeepOps Kubernetes Deployment Guidehere](https://github.com/NVIDIA/deepops/blob/master/docs/kubernetes-cluster.md) for more information.
    
    Verify that Kubernetes clustering is working with "kubectl get nodes" command:
    ```sh
    nvidia@mgmt01:~$ kubectl get nodes
    NAME     STATUS   ROLES    AGE    VERSION
    mgmt01   Ready    master   1d8h   v1.21.6
    gpu01    Ready    <none>   1d8h   v1.21.6
    gpu02    Ready    <none>   1d8h   v1.21.6
    nvidia@mgmt01:~$
    ```
5. Deploy NVIDIA Network Operator
   Before runnng the playbook, please update "roles/nvidia-network-operator/vars/main.yml" file according to your hardware and network configuration, this is what we used in our value.yaml file:
   ```sh
   num_vf: 8
   vendor_id: "15b3"
   link_type: "ib"
   mtu: 4096

   intf_resources:
     - if_name: "ibs1"
       pf_name: "ibs1"
       res_name: "resibs1"
       ip_addr: "192.168.101.0/24"
     - if_name: "ibp12s0"
       pf_name: "ibp12s0"
       res_name: "resibp12s0"
       ip_addr: "192.168.102.0/24"
       ...
    ## "15b3" is Mellanox vendor code for ConnectX cards.
    ```
   Run the playbook:
    ```sh
   ansible-playbook playbooks/k8s-cluster/nvidia-network-operator.yaml
   ```
   
## Running the Workload

The cluster is ready to run multi-node workload in the cluster, One last thing is to add related interface configuration to the job file before launching your job. 

### Using SR-IOV interfaces

Below is what is the section of the job file looks like after adding relevant SR-IOV interface configuration. A docker private registry at 192.168.1.11 is used to host and manage the testing images in this example, please refer to this docker [document](https://docs.docker.com/registry/deploying/) for more details. Other container registry can be used as well.

```sh
Worker:
  replicas: 2
  template:
    metadata:
      annotations:
        k8s.v1.cni.cncf.io/networks: ibs1,ibp12s0
    spec:
      containers:
      - image: 192.168.1.11:5000/nccl-test
        name: nccl-benchmark
        securityContext:
          capabilities:
            add: [ "IPC_LOCK" ]
        resources:
          limits:
            nvidia.com/resibs1: "1"
            nvidia.com/resibp12s0: "1"
            nvidia.com/gpu: 8
        env:
        - name: NCCL_IB_DISABLE
          value: "0"
        - name: NCCL_NET_GDR_LEVEL
          value: "2"
```
"nvidia.com/resibs1" is the network resource where SR-IOV is enabled, it's also defined in "roles/nvidia-network-operator/vars/main.yaml" in this repository.

Now you can launch the job with your familiar Kubernetes command:

```sh
nvidia@mgmt01:~$ kubectl create -f nccl-test.yaml
```
### NCCL AllReduce Test Result

Below is a NCCL allreduce test result run on a DGX-1 cluster with 4 x 100G HCA interfaces. NCCL deliveries near line rate performance:

```sh
#                                                       out-of-place                       in-place
#       size         count      type   redop     time   algbw   busbw  error     time   algbw   busbw  error
#        (B)    (elements)                       (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
           8             2     float     sum    42.96    0.00    0.00  2e-07    32.87    0.00    0.00  1e-07
          16             4     float     sum    37.39    0.00    0.00  1e-07    32.98    0.00    0.00  1e-07
          32             8     float     sum    39.11    0.00    0.00  1e-07    34.82    0.00    0.00  1e-07
          64            16     float     sum    41.81    0.00    0.00  1e-07    34.66    0.00    0.00  6e-08
         128            32     float     sum    33.23    0.00    0.01  6e-08    38.19    0.00    0.01  6e-08
         256            64     float     sum    38.90    0.01    0.01  6e-08    33.20    0.01    0.01  6e-08
         512           128     float     sum    34.32    0.01    0.03  6e-08    32.05    0.02    0.03  6e-08
        1024           256     float     sum    38.84    0.03    0.05  2e-07    37.46    0.03    0.05  2e-07
        2048           512     float     sum    36.95    0.06    0.10  2e-07    37.23    0.06    0.10  2e-07
        4096          1024     float     sum    39.67    0.10    0.19  5e-07    42.29    0.10    0.18  5e-07
        8192          2048     float     sum    47.62    0.17    0.32  5e-07    45.39    0.18    0.34  5e-07
       16384          4096     float     sum    45.50    0.36    0.68  5e-07    46.02    0.36    0.67  5e-07
       32768          8192     float     sum    53.73    0.61    1.14  5e-07    58.91    0.56    1.04  5e-07
       65536         16384     float     sum    62.27    1.05    1.97  5e-07    66.98    0.98    1.83  5e-07
      131072         32768     float     sum    69.76    1.88    3.52  5e-07    74.26    1.76    3.31  5e-07
      262144         65536     float     sum    72.19    3.63    6.81  5e-07    77.27    3.39    6.36  5e-07
      524288        131072     float     sum    106.2    4.94    9.26  5e-07    104.7    5.01    9.39  5e-07
     1048576        262144     float     sum    127.9    8.20   15.38  5e-07    126.9    8.26   15.49  5e-07
     2097152        524288     float     sum    154.5   13.58   25.46  5e-07    153.4   13.67   25.63  5e-07
     4194304       1048576     float     sum    228.7   18.34   34.38  5e-07    229.6   18.27   34.25  5e-07
     8388608       2097152     float     sum    399.6   20.99   39.36  5e-07    407.6   20.58   38.59  5e-07
    16777216       4194304     float     sum    751.9   22.31   41.84  5e-07    749.7   22.38   41.96  5e-07
    33554432       8388608     float     sum   1437.3   23.35   43.77  5e-07   1431.7   23.44   43.94  5e-07
    67108864      16777216     float     sum   2677.0   25.07   47.00  5e-07   2732.0   24.56   46.06  5e-07
   134217728      33554432     float     sum   5292.9   25.36   47.55  5e-07   5300.1   25.32   47.48  5e-07
   268435456      67108864     float     sum    10540   25.47   47.75  5e-07    10545   25.46   47.73  5e-07
   536870912     134217728     float     sum    21099   25.45   47.71  5e-07    21010   25.55   47.91  5e-07
  1073741824     268435456     float     sum    41998   25.57   47.94  5e-07    41949   25.60   47.99  5e-07
  2147483648     536870912     float     sum    83868   25.61   48.01  5e-07    83730   25.65   48.09  5e-07
  4294967296    1073741824     float     sum   167263   25.68   48.15  5e-07   167543   25.64   48.07  5e-07
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 18.5822
```
   Enjoy!

   > Note: This is not a performance benchmark testing so we don't fine tune any hardware and software stack parameters. The results are considered as an out-of-box number that can be observed in regular customer environments with the solution documented here. For more information about NCCL, see the following [blog post](https://devblogs.nvidia.com/scaling-deep-learning-training-nccl/).

