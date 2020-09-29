Role Name: roce_backend
=======================

The Role is added to K8s cluster availability to use in POD deployment RoCE enabled additional NIC's which based on SR-IOV Virtual function.
For full Reference Deployment Guide please look - https://docs.mellanox.com/pages/releaseview.action?pageId=15049828

Requirements
------------
1. SR-IOV supported server platform 
2. Enable SR-IOV in the NIC firmware (For Mellanox adapters plase refer to https://community.mellanox.com/s/article/howto-configure-sr-iov-for-connectx-4-connectx-5-with-kvm--ethernet-x#jive_content_id_I_Enable_SRIOV_on_the_Firmware)
3. Kubernetes cluster is deployed by DeepOps deployment tools 

You should consult your hardware documentation for the BIOS specific settings in order to enable support for SR-IOV networking.

Network requirements
-------------------
The Role is required an additional Ethernet fabric for high-performance POD network interfaces. Recommended scale-out L2 fabric with VXLAN-BGP-EVPN over Mellanox Onyx. Network deployment example with switch configuration files can be found - https://github.com/Mellanox/roce_backend_at_scale. 


Role Variables
--------------

The settable variables for the role must be provided in vars/main.yml.

1. SR-IOV resources for high-performance POD network interfaces.
Each section of sriov_resources must have: 
	pf_name – physical adapter interface name
	vlan_id – VLAN ID for virtual function interfaces
	res_name – resource pool name 
	network_name – network name for annotation in POD YAML configuration 

Please configure SRIOV interfaces depending on your deployment.
Below provided sriov_resources example for four interfaces.
```
sriov_resources:
  - pf_name: "ens9f0"
    vlan_id: 111
    res_name: "sriov_111"
    network_name: "sriov111"
  - pf_name: "ens10f0"
    vlan_id: 112
    res_name: "sriov_112"
    network_name: "sriov112"
  - pf_name: "ens11f0"
    vlan_id: 113
    res_name: "sriov_113"
    network_name: "sriov113"
  - pf_name: "ens12f0"
    vlan_id: 114
    res_name: "sriov_114"
    network_name: "sriov114"
```
2. Hardware adapter vendor - vendor. Default - 15b3.

vendor: "15b3"

3. Virtual function device ID - dev_id. 
   Default - "MT28908 Family [ConnectX-6 Virtual Function]". 
   Detailed information about all Mellanox Device ID can be found - https://devicehunt.com/view/type/pci/vendor/15B3
```
Supported values 
    101c - MT28908 Family [ConnectX-6 Virtual Function]
    101a - MT28800 Family [ConnectX-5 Ex Virtual Function]
    1018 - MT27800 Family [ConnectX-5 Virtual Function]   
    1016 - MT27710 Family [ConnectX-4 Lx Virtual Function]
    1014 - MT27700 Family [ConnectX-4 Virtual Function]

dev_id: "101c"
```
4. Amount of Virtual function for activation - num_vf.

num_vf: 8

5. Mellanox Ofed version, site place and image name - mofed_version, mofed_site_place, mofed_file_name.
```
#Mellanox OFED parameters
mofed_version: "4.7-3.2.9.0"
mofed_site_place: "MLNX_OFED-4.7-3.2.9.0"
mofed_file_name: "MLNX_OFED_LINUX-4.7-3.2.9.0-ubuntu18.04-x86_64.iso"
```


Dependencies
------------

During the installation process the Role is used Deepops config/inventory file for deployment and provisioning the Kubernetes components. 

Role components 
---------------

The Role installing following components:
1. Mellanox OFED with Virtual function activation
2. Python modules
3. Multus CNI for attaching multiple network interfaces to pod
4. Universal SR-IOV device plugin with specific configuration
5. Universal SR-IOV CNI 
6. Specific Network provisioning with NetworkAttachmentDefinition
7. DHCP CNI for providing IP addresses for SR-IOV based NIC's in pod deployment from existing infrastructure  
8. The latest version Kubeflow/MPI-Operator



Role deployment
---------------

With root user:
```
ansible-playbook -l k8s-cluster playbooks/k8s-cluster/roce.yaml
```

With standard user:
```
ansible-playbook -l k8s-cluster playbooks/k8s-cluster/roce.yaml -u "username" -k -K
```

License
-------

BSD

Author Information
------------------
author: Vitaliy Razinkov
email: vitaliyra@mellanox.com
company: Mellanox Technologies

