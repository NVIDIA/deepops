High-Performance RoCE Implementation in Multi-Node Kubernetes Cluster
===

## Summary

   RDMA over Converged Ethernet (RoCE) can be used as an interconnect technology in multi-node Kubernetes cluster for ML/AI workload. This document will walk through some of the design considerations, configuration steps and lab test results to help you better understand the solution and make an informed decision when you consider running your ML/AI workload on RoCE interconnect technology. The whole solution can be deployed with various DeepOps Kubernetes cluster deployment scripts and playbooks.

## Solution Overview and Scope

   The goal of this solution to provide a high performance GPU on-demands Ethernet based multi-node Kubernetes environment so data scientists, researchers and developers can launch their ML/AI workloads quickly on a containerized environment without worrying about underlying computation infrastructure's compatibility matrix on different hardware, software and performance. This implementation guide is built up with 3 nodes cluster in a lab environment, all the detailed hardware, software requirements list here are pertinent to this environment but can be served as a general reference on where you see fit to your particular case. In this 3-node Kubernetes cluster, One DGX-1 is configured exclusively as a Kubernetes master node, ideally a well-designed Kubernetes HA cluster should have minimal 3 master nodes formed a stacked control plane, but that's not the focus of this exercise and one master node doesn't have any functional impact on our pod, especially for the RoCE functions. But it's recommended to follow general HA best practice design in a production environment.  Two other DGX-1s are configured as GPU worker nodes. Each GPU worker node is equipped with 8*V100 Tesla GPUs and two Mellanox ConnectX-5 VPI dual mode (InfiniBand or Ethernet) 100G network cards, which are operated in Ethernet mode in this lab. A Mellanox Spectrum Ethernet switch is used to connect those two worker nodes. A separate management switch is provisioned to provide housekeeping management functions.  Opensource Kubernetes with Nvidia GPU plugins are running on top of those 3 nodes to provide containerized GPU-on-demand services for various ML/AI workload. Open MPI, Nvidia NCCL with CUDA, ResNet image classification with Tensorflow and Horovod framework are used as application workload to validate solution, especially the performance. 

## RoCE Design Considerations

   100GbE RoCE is used here to provide the interconnect between two GPU worker nodes. RoCE provides the Remote Direct Memory Access (RDMA) across the Ethernet and IP network from one host to another with reduced latency and lower CPU overhead. Traditionally Ethernet and IP network are considered as a "lossy" network since they're not designed to provide an end-to-end lossless transmission, the packet drops occurred during the transmission are supposed to be taken care of by upper layer protocols. RoCE switch remedies this by utilizing PFC and ECN to manage the traffic flow and congestions. In our lab we have taken following considerations into our implementation:

   * Enable and configure RoCE properly wherever it's applicable:
     * Use RoCE NICs in servers with appropriate drivers installed. 
     * Use RoCE capable high performance non-blocking Ethernet switch supporting PFC and ECN based traffic management functions.
     * Software libraries that can take advantage RoCE.
   * LACP or any link bundle with multiple NICs are not recommended since it doesn't work well with RoCE and RDMA in general. It's recommended to have each NIC on a separate subnet.  
   * Ideally each NIC should be on a separate "rail" to form a multi-rail topology. At the minimal, NICs on the same PCIe switch and NUMA node should spread out to different physical switches. please refer to server hardware block diagram on how the NICs and GPUs are connected internally.
   * SRIOV with RoCE is the key technology to enable Kubernetes pod to achieve near line rate performance and low latency. Single Root I/O Virtualization (SRIOV) virtualize a single physical RoCE NIC into multiple virtual RoCE interfaces (it's called VF in SRIOV's terminology) and directly attaches it to Kubernetes pod without going through the Linux kernel, so higher performance and lower latency can be achieved because the entire data path is now bypassing the Linux kernel. 

## Key Hardware & Software Requirements

   * 1 x DGX-1 server used as both Kubernetes master node and DeepOps management node
   * 2 x DGX-1 servers used as Kubernetes GPU worker nodes:
     * 8 x Tesla V100 GPU with total of 256GB (32GB x 8) HBM2 GPU memory
     * 2 x Mellanox ConnectX-5 VPI 100G NICs (configured as RoCE)
   * 1 x Mellanox Spectrum SN2700 non-blocking 3.2T RoCE Ethernet switch
   * Software components:
     * [NVIDIA DGX OS 4.4](https://docs.nvidia.com/dgx/dgx-os-server-release-notes/index.html#dgx-os-server-sw-versions)
     * Kubernetes v.1.15 and v.1.16 
     * latest MPI operator for Kubernetes 
     * latest Multus CNI to support multiple interfaces
     * latest SRIOV CNI and device plugin
     * latest Nvidia container toolkit
     * Nvidia NCCL 2.5.6 with CUDA 10.1
     * OpenMPI 3.1.5 and 4.0.0
     * TensorFlow 2.1.0
     * Mellanox Onyx v3.8 for SN2700
     * MOFED 4.7-3.2.9.0 and 4.6-1.0.1.1 for Mellanox ConnectX-5
   * Internet access for software package upgrade


## Configuration Steps

add switch PFC, ECN configuration

1. Configure Ethernet switch to support RoCE.

   A dedicated Mellanox SN2700 is used in our RoCE Kubernetes lab to connect two worker nodes, following "lossy" fabric ECN configuration is applied to the switch:

   ```sh
   interface ethernet 1/1-1/3 traffic-class 3 congestion-control ecn minimum-absolute 150 maximum-absolute 1500
   ```
   > NOTE: More More sophisticated QoS and traffic management technique should be carefully designed and applied in large scale mixed traffic environment.

2. Install a supported operating system on all nodes.

   Install a supported operating system on all servers utilizing the [DGXie](/docs/pxe/dgxie-container.md) provisioning container, via a 3rd-party solution (i.e. [MAAS](https://maas.io/), [Foreman](https://www.theforeman.org/)), or server BMC/console.

   > NOTE: During OS installation, it is ideal if the identical user/password is configured. Otherwise, follow step 4 below to create an identical user across all nodes in the cluster.


3. Verify SRIOV is enabled in server BIOS and RoCE is working on the physical NIC level

   All DGX servers should have SRIOV enabled in BIOS. The installed ConnectX-5 VPI NIC card should come with RoCE drivers installed and have the correct settings for ECN and CNP strict priority queue. 

   To verify RoCE is working on the NICs between two worker nodes, choose one GPU worker node as server, issue following command:

   ```sh
   # Acting as RDMA IB verb server
   nvidia@gpu01:~$ ib_write_bw -R -d mlx5_0 --report_gbits -x 3
   ```

   Choose another GPU worker node as client, issue following command:

   ```sh
   # Acting as RDMA IB verb client
   nvidia@gpu02:~$ ib_write_bw -R -d mlx5_0  10.10.11.11 --report_gbits -x 3
   ```
   You should see something similar to this:

   ```sh
                        RDMA_Write BW Test
    Dual-port       : OFF          Device         : mlx5_0
    Number of qps   : 1            Transport type : IB
    Connection type : RC           Using SRQ      : OFF
    TX depth        : 128
    CQ Moderation   : 1
    Mtu             : 4096[B]
    Link type       : Ethernet
    GID index       : 3
    Max inline data : 0[B]
    rdma_cm QPs     : ON
    Data ex. method : rdma_cm
    ---------------------------------------------------------------------------------------
    local address: LID 0000 QPN 0x025d PSN 0x5cac14
    GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:10:11:12
    remote address: LID 0000 QPN 0x025d PSN 0xe849fe
    GID: 00:00:00:00:00:00:00:00:00:00:255:255:10:10:11:11
    ---------------------------------------------------------------------------------------
    #bytes     #iterations    BW peak[Gb/sec]    BW average[Gb/sec]   MsgRate[Mpps]
    Conflicting CPU frequency values detected: 1200.535000 != 1251.336000. CPU Frequency is not max.
    65536      5000             92.42              92.40              0.176230
    ---------------------------------------------------------------------------------------
   ```
   So we're getting 92.40Gb/s out of a 100Gbps NIC.

4. Set up your management node.

   Install Ansible and required software on the management node.

   DeepOps uses a single management node deploy all other software to the cluster. This process may take several minutes as ansible-galaxy roles are downloaded and python packages are installed. For more information on Ansible and why we use it, consult the [Ansible Guide](ANSIBLE.md).

   ```sh
   # Install software prerequisites and copy default configuration
   # Copies ./config.example to ./config, if none exists
   ./scripts/setup.sh
   ```

5. Edit the Ansible inventory file

   Edit the Ansible inventory file and verify connectivity to all nodes.

   Ansible uses an inventory which outlines the servers in the cluster and a set of group variables which playbooks use to customize deployment. Running `./scripts/setup.sh` in the previous step should have created the `config` directory.
      
   ```sh
   # Modify the Ansible inventory file
   # Especially the 'all', 'kube-master', 'etcd', 'kube-node' and 'k8s-cluster' sections
   vi config/inventory
   ```

   > NOTE: Be warned that `/etc/hostname` and `/etc/hosts` on each host will be modified to the name(s) specified in the inventory file, so it is best to use the actual names of the hosts.

   When modifying the inventory, if the hosts are not accessible from the management node by their hostname, supply an an `ansible_host`. For example:

   ```yml
   # in config/inventory...

   [all]
   mgmt01     ansible_host=192.168.1.10
   gpu01      ansible_host=192.168.2.11
   gpu02      ansible_host=192.168.2.11
   ...

   [kube-master]
   mgmt01

   [kube-node]
   gpu01
   gpu02

   ```

6. Add or modify user(s) across cluster

   The ansible scripts assume a consistent user which has access to all nodes in the cluster.

   > Note: If a user with the same username, uid, and password exists on each node, skip this step. It is critical for the user to exist with the same uid across all nodes.

   ```sh
   # The default user is `nvidia` with password `deepops`
   # Modify this user/password as desired
   vi config/group_vars/all.yml
   ```

   Run the users playbook to create/modify the user across all nodes.

   ```sh
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u <user>`
   ansible-playbook -b playbooks/generic/users.yml
   ```

7. Verify the configuration

   ```sh
   ansible all -m raw -a "hostname"
   ```

8. Deploying and verifying Kubernetes cluster

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
   gpu01    Ready    <none>   7d5h   v1.16.7
   gpu02    Ready    <none>   7d5h   v1.16.7
   mgmt01   Ready    master   7d5h   v1.16.7
   nvidia@mgmt01:~$
   ```

9. Deploy SRIOV RoCE for Kubernetes Cluster

   Use DeepOps RoCE_backend deployment scripts to deploy following components to the Kubernetes cluster, those steps are also described in detail in this [doc](https://github.com/NVIDIA/deepops/tree/master/roles/roce_backend):

   * Upgrade Mellanox OFED driver package to the appropriate version to active SRIOV VFs
   * Multus CNI to support multiple NICs in Kubernetes pod
   * SR-IOV CNI and SRIOV device plugin
   * DHCP CNI for pod IP addresses management for SR-IOV RoCE interfaces
   * Latest MPI-Operator

   Modify roles/roce_backend/vars/main.yml file, update the variables according to your hardware and network configuration. This is the parameters we used:

   ```sh
   sriov_resources:
     - pf_name: "enp5s0"
       vlan_id: 111
       res_name: "sriov_111"
       network_name: "sriov111"
     - pf_name: "enp132s0"
       vlan_id: 112
       res_name: "sriov_112"
       network_name: "sriov112"

   # NOTE: "15b3" is Mellanox vendor code and "1018" is for MT27800 Family [ConnectX-5 Virtual Function]

   vendor: "15b3"
   dev_id: "1018"
   num_vf: 8
   ```
   Run following script to deploy SRIOV RoCE functions:

   ```sh
   nvidia@mgmt01:~/deepops_0322$ ansible-playbook -l k8s-cluster playbooks/k8s-cluster/roce.yaml
   ```

   If using a different username and SSH key-based authentication haven't set up, try to use `-u <user> -k -K` when you run the script.

10. Using SRIOV RoCE interfaces  


   The cluster is ready to run multi-node workload with all SRIOV RoCE related components deployed. One last thing is to add related configuration to the job file before launching your job.  Below is what is the section of the job file looks like after adding relevant SRIOV interface configuration. We We built a docker private registry at 192.168.100.10 to host and manage our testing images, please refer to this docker [document](https://docs.docker.com/registry/deploying/) for more details. 

   ```sh
    Worker:
      replicas: 2
      template:
        metadata:
          annotations:
            k8s.v1.cni.cncf.io/networks: sriov111,sriov112
        spec:
          containers:
          - image: 192.168.100.10:5000/nccl-roce-test
            name: nccl-benchmark
            securityContext:
              capabilities:
                add: [ "IPC_LOCK" ]
            resources:
              limits:
                intel.com/sriov_111: 1
                intel.com/sriov_112: 1
                nvidia.com/gpu: 8
            env:
            - name: NCCL_IB_DISABLE
              value: "0"
            - name: NCCL_NET_GDR_LEVEL
              value: "2"

   ```

   Now you can launch the job with your familiar Kubernetes command:

   ```sh
   nvidia@mgmt01:~$ kubectl create -f nccl-roce-test.yaml
   ```

## Test Results

   The first suites of test we did is to run a multi-node Nvidia NCCL tests with Open MPI on Kubernetes. Run nccl testing job with added SRIOV RoCE interface configuration shown above, if the test is successful you should expect to see output similar to this:(NCCL ring test):

   ```sh
   #
   #                                                     out-of-place                       in-place
   #       size         count    type   redop     time   algbw   busbw  error     time   algbw   busbw  error
   #        (B)    (elements)                     (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
              8             2   float     sum   2193.5    0.00    0.00  2e-07    132.2    0.00    0.00  2e-07
             16             4   float     sum    84.54    0.00    0.00  2e-07    576.2    0.00    0.00  1e-07
             32             8   float     sum    121.9    0.00    0.00  1e-07    83.31    0.00    0.00  1e-07
             64            16   float     sum    577.2    0.00    0.00  1e-07    129.1    0.00    0.00  6e-08
            128            32   float     sum    88.38    0.00    0.00  6e-08    580.1    0.00    0.00  6e-08
            256            64   float     sum    130.4    0.00    0.00  6e-08    92.28    0.00    0.01  6e-08
            512           128   float     sum    575.6    0.00    0.00  6e-08    128.2    0.00    0.01  6e-08
           1024           256   float     sum    89.06    0.01    0.02  4e-07    609.0    0.00    0.00  4e-07
           2048           512   float     sum    132.3    0.02    0.03  5e-07    89.53    0.02    0.04  5e-07
           4096          1024   float     sum    587.4    0.01    0.01  5e-07    139.8    0.03    0.05  5e-07
           8192          2048   float     sum    97.89    0.08    0.16  5e-07    590.0    0.01    0.03  5e-07
          16384          4096   float     sum    147.4    0.11    0.21  5e-07    108.7    0.15    0.28  5e-07
          32768          8192   float     sum    598.1    0.05    0.10  5e-07    146.5    0.22    0.42  5e-07
          65536         16384   float     sum    121.8    0.54    1.01  5e-07    646.9    0.10    0.19  5e-07
         131072         32768   float     sum    217.1    0.60    1.13  5e-07    180.2    0.73    1.36  5e-07
         262144         65536   float     sum    637.5    0.41    0.77  5e-07    252.6    1.04    1.95  5e-07
         524288        131072   float     sum    182.6    2.87    5.38  5e-07    657.4    0.80    1.50  5e-07
        1048576        262144   float     sum    307.5    3.41    6.39  5e-07    225.1    4.66    8.74  5e-07
        2097152        524288   float     sum    782.3    2.68    5.03  5e-07    387.7    5.41   10.14  5e-07
        4194304       1048576   float     sum    503.0    8.34   15.63  5e-07    979.7    4.28    8.03  5e-07
        8388608       2097152   float     sum    906.8    9.25   17.34  5e-07    847.9    9.89   18.55  5e-07
       16777216       4194304   float     sum   2041.5    8.22   15.41  5e-07   1618.6   10.37   19.44  5e-07
       33554432       8388608   float     sum   2851.1   11.77   22.07  5e-07   3597.8    9.33   17.49  5e-07
       67108864      16777216   float     sum   5687.1   11.80   22.13  5e-07   5611.8   11.96   22.42  5e-07
      134217728      33554432   float     sum    11461   11.71   21.96  5e-07    11121   12.07   22.63  5e-07
      268435456      67108864   float     sum    22022   12.19   22.86  5e-07    22491   11.94   22.38  5e-07
      536870912     134217728   float     sum    43963   12.21   22.90  5e-07    43998   12.20   22.88  5e-07
     1073741824     268435456   float     sum    88429   12.14   22.77  5e-07    87932   12.21   22.90  5e-07
     2147483648     536870912   float     sum   175667   12.22   22.92  5e-07   176189   12.19   22.85  5e-07
   # Out of bounds values : 0 OK
   # Avg bus bandwidth    : 7.76739
   #
   ```

   > Note: This is not a performance benchmark testing so we don't fine tune any hardware and software stack parameters, application, etc. The results are considered as an "out-of-box" number that can be observed in regular customer environments with the solution we documented here. For more background about NCCL, see the following [blog post](https://devblogs.nvidia.com/scaling-deep-learning-training-nccl/). 

   Horovod is a distributed deep learning training framework for TensorFlow, Keras, PyTorch, and Apache MXNet. Horovod project team choose MPI over distributed TensorFlow with parameter servers because MPI model is much easy and straightforward to implement. Following Horovod's GitHub [document](https://github.com/horovod/horovod), we also did a few TensorFlow ResNet image classification tests with Horovod build-in benchmark test, the results are shown below:


   ```sh
   Running benchmark...
   Iter #0: 199.4 img/sec per GPU
   Iter #1: 248.1 img/sec per GPU
   Iter #2: 247.6 img/sec per GPU
   Iter #3: 246.4 img/sec per GPU
   Iter #4: 246.4 img/sec per GPU
   Iter #5: 248.3 img/sec per GPU
   Iter #6: 186.1 img/sec per GPU
   Iter #7: 243.2 img/sec per GPU
   Iter #8: 237.1 img/sec per GPU
   Iter #9: 244.8 img/sec per GPU
   Img/sec per GPU: 234.8 +-42.0
   Total img/sec on 16 GPU(s): 3756.0 +-672.7
   ```


## Performance Validation with Baremetal and Non-RoCE Kubernetes Pods

   Additional tests are performed to compare the performance on multi-node baremetal servers and non-RoCE kubernetes pods. For multi-node baremetal server NCCL testing, we follow the documentations on those sites to install and compile NCCL and Open MPI:  https://github.com/NVIDIA/nccl and https://www.open-mpi.org/. For non-RoCE Kubernetes pods testing, we simply detached the SRIOV/RoCE interfaces from Kubernetes job file so NCCL will run over traditional IP sockets. We run multiple tests in each scenarios to eliminates the outliers and the results show SRIOV with RoCE in Kubernetes can delivery the same performance as in baremetal servers.

NCCL Latency comparison (NCCL ring topology): 

![alt text](img/nccl_latency_ring.PNG "NCCL latency, ring")


NCCL Bandwidth comparison (NCCL ring topology): 

![alt text](img/nccl_bandwidth_ring.PNG "NCCL bandwidth, ring")

   > Note: The bare-metal results are overlapping with Kubernetes SRIOV+RoCE because the number is almost identical.

### Troubleshoot 

   NCCL tests usually runs pretty fast and can finish in a few minutes once the job is launched and pod is running, but in case you run into any problem that you want to troubleshoot, for example, if the job launching pod stays in "running" state for extended period of time or in "error" states, you can "describe" the pod or check the running log of the pod to get further information. Also it's helpful to enable NCCL debug information when you launch the job. 


   ```sh
   # Describe the pod 
   kubernetes describe pods nccl-benchmarks-launcher-your_number

   # Checking the running log of the pod 
   kubectl logs -f nccl-benchmarks-launcher-your_number
   
   # Enable NCCL debug information
   NCCL_DEBUG=INFO
   NCCL_DEBUG_SUBSYS=NET
   ```
