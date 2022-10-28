# NVIDIA Network Operator

Deploy NVIDIA Network Operator with DeepOps

- [NVIDIA Network Operator](#nvidia-network-operator)
  - [Overview](#overview)
  - [Requirements and Tested Environment:](#requirements-and-tested-environment)
  - [Deployment Steps](#deployment-steps)
  - [Running the Workload](#running-the-workload)
    - [Using SR-IOV interfaces](#using-sr-iov-interfaces)
    - [NCCL AllReduce Test Result](#nccl-allreduce-test-result)

## Overview

NVIDIA Network Operator leverages Kubernetes CRDs and Operator SDK to manage networking related components in Kuberenets cluster. One of the key components is SR-IOV, which partitions a single PCIe hardware into multiple Virtual Functions (VFs) and attach them directly to Kubernetes pods without going through the virtualization layer on the hosts, thus enables the high performance communication between workloads. High performance networking in Kuberentes also requires a few other components, such as multus-CNI, device drivers and plugins, etc, NVIDIA network operator aims to manage all those necessary components automatically under one operator frame work to simply the deployment, operation and management of NVIDIA networking for Kubernetes.

Here are the key components that NVIDIA network operator try to deploy together:

- SR-IOV Virtual Function (VF) activation
- Multus CNI
- SR-IOV CNI for kubernetes
- SR-IOV device plugin for kubernetes
- Multus CNI
- Helm chart for NVIDIA network operator

This playbook also install the latest Kubeflow/MPI-Operator, currently version v2beta1, for multi-node MPI jobs.

Currently only InfiniBand networking is supported in this implementation, RoCE networking support will be added shortly.

## Requirements and Tested Environment:

This playbook is developed and tested in following environments:

- NVIDIA DGX servers with DGX OS 5.1
- Mellanox ConnectX-6 VPI HCA
- Ansible 2.9.27 (deployed by DeepOps)
- Kubernetes v1.21.6 (deployed by DeepOps)
- Helm version v3.6.3 (deployed by DeepOps)
- NVIDIA network opertor v1.1.0
- InfiniBand networking. (Ethernet networking support will be added in the future.)

## Deployment Steps

1. Make sure underlying InfiniBand network works properly between Kubernetes nodes. It's recommended to run some bare metal micro benchmark testing to verify the IB network is working as expected, for example, NVIDIA perftest package can be used for that purpose.

2. Enabling IB port virtualization on IB opensm. This is done in an IB switch in the lab:

   ```bash
   IB_Switch (config) # ib sm virt enable
   ```

3. Verify SR-IOV is enabled in BIOS and HCAs.

   Use following commands to verify SR-IOV and VFs are enabled on ConnectX-6 HCAs, "0000:05:00.0" is the HCA's PCIe bus number.

   ```bash
   sudo mlxconfig -d 0000:05:00.0 q | grep -i "sriov\|vfs"
   ```

4. Set up Kubernetes cluster

   Kubernetes installation is done by DeepOps Ansible playbooks, For more information on Ansible and why we use it, consult the [Ansible Guide](ANSIBLE.md).

- Install and configure DeepOps on managemet node:

  ```bash
  git clone https://github.com/NVIDIA/deepops.git
  cd deepops/
  ./scripts/setup.sh
  vi config/inventory
  ```

  Configuring the Ansible inventory file by editing the "config/inventory" file, and verify connectivity to all nodes.

  > NOTE: Be warned that `/etc/hostname` and `/etc/hosts` on each host will be modified to the name(s) specified in the inventory file, so it is best to use the actual names of the hosts.

  When modifying the inventory, if the hosts are not accessible from the management node by their hostname, supply an an `ansible_host` with its IP address. Example of the inventory file:

  ```bash
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

  ```bash
  # The default user is `nvidia` with password `deepops`
  # Modify this user/password in config/group_vars/all.yaml as desired
  vi config/group_vars/all.yml
  ```

  Run the users playbook to create/modify the user across all nodes.

  ```bash
  # NOTE: If SSH requires a password, add: `-k`
  # NOTE: If sudo on remote machine requires a password, add: `-K`
  # NOTE: If SSH user is different than current user, add: `-u <user>`
  ansible-playbook -b playbooks/generic/users.yml
  ```

  Verify the configuration

  ```bash
  ansible all -m raw -a "hostname"
  ```

- Deploying and verifying Kubernetes cluster
  Install Kubernetes using Ansible and Kubespray

  ```bash
  # NOTE: If SSH requires a password, add: `-k`
  # NOTE: If sudo on remote machine requires a password, add: `-K`
  # NOTE: If SSH user is different than current user, add: `-u ubuntu`
  ansible-playbook -l k8s-cluster playbooks/k8s-cluster.yml
  ```

  Please refer to [DeepOps Kubernetes Deployment Guidehere](https://github.com/NVIDIA/deepops/blob/master/docs/kubernetes-cluster.md) for more information.

  Verify that Kubernetes clustering is working with "kubectl get nodes" command:

  ```bash
  nvidia@mgmt01:~$ kubectl get nodes
  NAME     STATUS   ROLES    AGE    VERSION
  mgmt01   Ready    master   1d8h   v1.21.6
  gpu01    Ready    <none>   1d8h   v1.21.6
  gpu02    Ready    <none>   1d8h   v1.21.6
  nvidia@mgmt01:~$
  ```

5. Deploy NVIDIA Network Operator
   Before runnng the playbook, please update "roles/nvidia-network-operator/vars/main.yml" file according to your hardware and network configuration, this is what we used in our value.yaml file:

   ```yaml
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

Below is what is the section of the job file looks like after adding relevant SR-IOV interface configuration. The Dockerfile used to build the "docker.io/deepops/mpi-nccl-test" container is also available in this DeepOps git repository.

```yaml
apiVersion: kubeflow.org/v2beta1
kind: MPIJob
metadata:
  name: nccltest
spec:
  slotsPerWorker: 8
  runPolicy:
    cleanPodPolicy: Running
  mpiReplicaSpecs:
    Launcher:
      replicas: 1
      template:
        spec:
          containers:
            - image: docker.io/deepops/mpi-nccl-test:latest
              name: nccltest
              imagePullPolicy: IfNotPresent
              command:
                - sh
                - "-c"
                - |
                  /bin/bash << 'EOF'
                  mpirun --allow-run-as-root \
                    -np 32 \
                    -bind-to none -map-by slot \
                    -x NCCL_DEBUG=INFO \
                    -x NCCL_ALGO=RING \
                    -x NCCL_IB_DISABLE=0 \
                    -x LD_LIBRARY_PATH \
                    -x PATH \
                    -mca pml ob1 \
                    -mca btl self,tcp \
                    -mca btl_tcp_if_include 192.168.0.0/16 \
                    -mca oob_tcp_if_include 172.29.0.0/16 \
                    /nccl_tests/build/all_reduce_perf -b 8 -e 4G -f2 -g 1 \
                    && sleep infinity
                  EOF
```

"nvidia.com/resibs1" is the network resource where SR-IOV is enabled, it's also defined in "roles/nvidia-network-operator/vars/main.yaml" in this repository.

Alternatively, a local private docker registry can also be used in an air-gapped environment where docker.io is not accessible, In following example, A docker private registry at 192.168.1.11 is used to host and manage the testing images, please refer to this docker [document](https://docs.docker.com/registry/deploying/) for more details.

```yaml
containers:
  - image: 192.168.1.11:5000/nccl-test:latest
    name: nccltest
    imagePullPolicy: IfNotPresent
```

Now you can launch the job with your familiar Kubernetes command:

```bash
nvidia@mgmt01:~$ kubectl create -f nccl-test.yaml
```

### NCCL AllReduce Test Result

Below is a NCCL allreduce test result run on between on a DGX A100 Kubernetes cluster between 2 nodes with 8 x 200G HCA (ConnectX-6 HDR) interfaces each. NCCL deliveries near line rate performance: NCCL bandwidth 188.53 GB/s between 8 interfaces translats to 188.53 Gbps/interfaces, 94.27% of theoretical maximum performance.

```console
#
#                                                       out-of-place                       in-place
#       size         count      type   redop     time   algbw   busbw  error     time   algbw   busbw  error
#        (B)    (elements)                       (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
           8             2     float     sum    38.63    0.00    0.00  2e-07    38.85    0.00    0.00  1e-07
          16             4     float     sum    38.14    0.00    0.00  1e-07    36.62    0.00    0.00  1e-07
          32             8     float     sum    37.90    0.00    0.00  1e-07    40.26    0.00    0.00  1e-07
          64            16     float     sum    40.47    0.00    0.00  1e-07    39.86    0.00    0.00  6e-08
         128            32     float     sum    40.52    0.00    0.01  6e-08    40.00    0.00    0.01  6e-08
         256            64     float     sum    39.99    0.01    0.01  6e-08    39.37    0.01    0.01  6e-08
         512           128     float     sum    41.67    0.01    0.02  6e-08    39.85    0.01    0.02  6e-08
        1024           256     float     sum    40.97    0.02    0.05  2e-07    49.81    0.02    0.04  2e-07
        2048           512     float     sum    45.93    0.04    0.08  5e-07    44.64    0.05    0.09  5e-07
        4096          1024     float     sum    49.16    0.08    0.16  5e-07    48.40    0.08    0.16  5e-07
        8192          2048     float     sum    65.14    0.13    0.24  5e-07    53.92    0.15    0.28  5e-07
       16384          4096     float     sum    57.43    0.29    0.53  5e-07    57.02    0.29    0.54  5e-07
       32768          8192     float     sum    62.10    0.53    0.99  5e-07    61.67    0.53    1.00  5e-07
       65536         16384     float     sum    77.12    0.85    1.59  5e-07    87.13    0.75    1.41  5e-07
      131072         32768     float     sum    101.0    1.30    2.43  5e-07    113.0    1.16    2.17  5e-07
      262144         65536     float     sum    121.5    2.16    4.04  5e-07    131.6    1.99    3.73  5e-07
      524288        131072     float     sum    135.2    3.88    7.27  5e-07    127.7    4.11    7.70  5e-07
     1048576        262144     float     sum    120.1    8.73   16.37  5e-07    119.3    8.79   16.48  5e-07
     2097152        524288     float     sum    137.2   15.29   28.67  5e-07    139.7   15.01   28.14  5e-07
     4194304       1048576     float     sum    165.8   25.29   47.43  5e-07    165.4   25.36   47.54  5e-07
     8388608       2097152     float     sum    209.2   40.09   75.17  5e-07    207.4   40.45   75.84  5e-07
    16777216       4194304     float     sum    301.9   55.57  104.19  5e-07    301.9   55.57  104.18  5e-07
    33554432       8388608     float     sum    536.0   62.60  117.38  5e-07    531.0   63.20  118.49  5e-07
    67108864      16777216     float     sum    918.0   73.11  137.08  5e-07    902.8   74.33  139.37  5e-07
   134217728      33554432     float     sum   1603.7   83.69  156.92  5e-07   1579.6   84.97  159.31  5e-07
   268435456      67108864     float     sum   2924.5   91.79  172.10  5e-07   2977.0   90.17  169.07  5e-07
   536870912     134217728     float     sum   5601.4   95.85  179.71  5e-07   5620.3   95.52  179.11  5e-07
  1073741824     268435456     float     sum    11085   96.87  181.62  5e-07    10994   97.67  183.13  5e-07
  2147483648     536870912     float     sum    21551   99.64  186.83  5e-07    21577   99.53  186.61  5e-07
  4294967296    1073741824     float     sum    42715  100.55  188.53  5e-07    42677  100.64  188.70  5e-07
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 53.7098

```

Enjoy!

> Note: This is not a performance benchmark testing so we don't fine tune any hardware and software stack parameters. The results are considered as an out-of-box number that can be observed in regular customer environments with the solution documented here. For more information about NCCL, see the following [blog post](https://devblogs.nvidia.com/scaling-deep-learning-training-nccl/).
