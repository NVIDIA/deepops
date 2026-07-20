# Architecture

Directory structure and explaination of this projects architecture

- [Architecture](#architecture)
  - [config.example](#configexample)
  - [docs](#docs)
  - [playbooks](#playbooks)
  - [roles](#roles)
  - [scripts](#scripts)
  - [src](#src)
  - [submodules](#submodules)
  - [virtual](#virtual)
  - [workloads](#workloads)

## config.example
Template folder for `config` folder generated after running `scripts/setup.sh`.
```bash
.
├── config.example
│   ├── containers
│   ├── files
│   ├── group_vars
│   ├── helm
│   ├── host_vars
│   ├── playbooks
│   └── pxe
```

## docs
Documentation for all DeepOps functionality. 
```bash
├── docs
│   ├── airgap
│   ├── cloud-native
│   ├── container
│   ├── deepops
│   ├── dev
│   ├── img
│   ├── k8s-cluster
│   ├── misc
│   ├── ngc-ready
│   ├── pxe
│   └── slurm-cluster
```


## playbooks
Playbooks run via Ansible as part of complete Slurm or Kubernetes installation or ad-hoc plays.
```bash
├── playbooks
│   ├── bootstrap
│   ├── container
│   ├── generic
│   ├── k8s-cluster
│   ├── nvidia-dgx
│   ├── nvidia-software
│   ├── provisioning
│   ├── slurm-cluster
│   └── utilities
```

 
## roles
Roles run as part of the various playbooks. Includes default values and tasks as well.
```bash
├── roles
│   ├── autofs
│   ├── cachefilesd
│   ├── dns-config
│   ├── docker-login
│   ├── docker-rootless
│   ├── easy-build
│   ├── easy-build-packages
│   ├── facts
│   ├── grafana
│   ├── k8s-internal-container-registry
│   ├── kerberos_client
│   ├── lmod
│   ├── mofed
│   ├── move-home-dirs
│   ├── netapp-trident
│   ├── nfs
│   ├── nfs-client-provisioner
│   ├── nginx-docker-registry-cache
│   ├── nhc
│   ├── nis_client
│   ├── nvidia_cuda
│   ├── nvidia_dcgm
│   ├── nvidia-dcgm-exporter
│   ├── nvidia-dgx
│   ├── nvidia-dgx-firmware
│   ├── nvidia-gpu-operator
│   ├── nvidia-gpu-operator-node-prep
│   ├── nvidia-gpu-tests
│   ├── nvidia_hpc_sdk
│   ├── nvidia-k8s-gpu-device-plugin
│   ├── nvidia-k8s-gpu-feature-discovery
│   ├── nvidia-mig-manager
│   ├── nvidia-network-operator
│   ├── nvidia-peer-memory
│   ├── ood-wrapper
│   ├── openmpi
│   ├── openshift
│   ├── prometheus
│   ├── prometheus-node-exporter
│   ├── prometheus-slurm-exporter
│   ├── pyxis
│   ├── roce_backend
│   ├── rsyslog_client
│   ├── rsyslog_server
│   ├── slurm
│   ├── spack
│   └── standalone-container-registry
```

## scripts
Various scripts used to setup environments and collect information. 
```bash
├── scripts
│   ├── airgap
│   ├── deepops
│   ├── generic
│   ├── k8s
│   ├── nginx-docker-cache
│   ├── pxe
│   └── slurm
```

## src
Contains some source material such as GPU Dashboard for Grafana. 
```bash
├── src
│   ├── containers
│   ├── dashboards
│   └── repo
```

## submodules
Submodules linked/versioned as part of KubeSpray and Packer-mass setup.
```bash
├── submodules
│   ├── kubespray
│   └── packer-maas
```

## virtual
Various resources for setting up virtual envs used with DeepOps
```bash
├── virtual
│   ├── scripts
│   └── vars_files
```

## workloads
Sample workloads which one can use after setting up their cluster. 
```bash
└── workloads
    ├── bit
    ├── examples
    ├── jenkins
    └── services
```
