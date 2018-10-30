# DeepOps Virtual

Set up a virtual cluster with DeepOps. Useful for...

1.) Learning how to deploy DeepOps on limited hardware
2.) Testing new features in DeepOps
3.) Tailoring DeepOps in a local environment before deploying it to the production cluster

## Prerequisites

Running DeepOps virtually assumes that the host machine's OS is Ubuntu 16.04 or greater. If this is
not the case, the `install_dependecies.sh` and `cluster_up.sh` scripts may be modified to work with
a different OS.

Also, using VMs and optionally GPU passthrough assumes that the host machine has been configured to
enable virtualization in the BIOS. For instructions on how to accomplish this, refer to the sections
at the bottom of this README: `Enabling virtualization and GPU passthrough`.

## Install dependencies

This project leverages vagrant and libvirt to spin up the appropriate VMs to model a DeepOps
cluster. To install the necessary dependencies, such as ansible, vagrant, libvirt, etc, run the
included `install_dependencies.sh` on the host machine...

```
$ ./install_dependencies.sh
```

## Start the cluster

To start the cluster, run the `cluster_up.sh` script...

```
$ ./cluster_up.sh
```

Vagrant will spin up three VMs - login01, mgmt01, and dgx01. Afterwards, the script will use ansible
to configure the nodes and set up DeepOps.

The script should complete without errors and three nodes should show up when running `virsh
list`...

```
$ virsh list
 Id    Name                           State
----------------------------------------------------
 7     vagrant_mgmt01                 running
 8     vagrant_login01                running
 9     vagrant_dgx01                  running
```

Connect to any of the nodes via vagrant ssh...

```
$ vagrant ssh dgx01
```

NOTE: not all playbooks and portions of DeepOps are currently deployed, this is a WIP

## Destroy the cluster

To destroy the cluster, run the `cluster_destroy.sh` script...

```
$ ./cluster_destroy.sh
```

Check that there are no running VMs using `virsh list`.

## Configure GPU passthrough

If your host machine has a GPU, it is possible to enable GPU passthrough to the dgx01 VM.

Run `lspci` to discover the appropriate bus...

```
$ lspci -nnk | grep NVIDIA
07:00.0 VGA compatible controller [0300]: NVIDIA Corporation Device [10de:15fc] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1195]
07:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:0fb1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1195]
08:00.0 VGA compatible controller [0300]: NVIDIA Corporation Device [10de:15fc] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1195]
08:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:0fb1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1195]
0e:00.0 VGA compatible controller [0300]: NVIDIA Corporation Device [10de:15fc] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1195]
0e:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:0fb1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1195]
0f:00.0 VGA compatible controller [0300]: NVIDIA Corporation Device [10de:15fc] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1195]
0f:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:0fb1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1195]
```

In this example, we've chosen the GPU at `08:00.0`.

In the `Vagrantfile`, uncomment the `v.pci` configuration and update it with a mapping to the bus
discovered with `lspci`...

```
v.pci :bus => '0x08', :slot => '0x00', :function => '0x0'

```

Destroy the virtual cluster (if it is running) and run cluster up again.

# Enabling virtualization and GPU passthrough

On many machines, virtualization and GPU passthrough are not enabled by
default. Follow these directions so that a virtual DeepOps cluster can start on your host machine
with GPU access on the VMs.

## BIOS and bootloader changes

To support KVM, we need GPU pass through. To enable GPU pass through, we need to enable VFIO support
in BIOS and Bootloader.

### BIOS changes

* Enable BIOS settings: Intel VT-d and Intel VT-x
* Enable BIOS support for large-BAR1 GPUs: 'MMIO above 4G' or 'Above 4G encoding', etc.

**DGX-2 SBIOS**
* VT-x:  enable
* VT-d:  enable
* MMIO above 4G: enable
* Intel AMT: disable

**DGX-1/1V SBIOS**
* VT-x: Intel RC Setup -> Processor Configuration -> VMX
* VT-d: Intel RC Setup -> IIO Configuration -> VT-d
* MMIO above 4G: Advanced -> PCI Subsystem Setting -> Above 4G Encoding

**DGX Station SBIOS**
* VT-x: 
* VT-d: 
* MMIO above 4G: verify virtualization support is enabled in the BIOS, by looking for vmx for Intel or svm for AMD
processors...

```
$ grep -oE 'svm|vmx' /proc/cpuinfo | uniq
vmx
```

### Bootloader changes

1. Add components necessary to load VFIO (Virtual Function I/O). VFIO is required to pass full
devices through to a virtual machine, so that Ubuntu loads everything it needs. Edit and add the
following to `/etc/modules` file:
```
pci_stub
vfio
vfio_iommu_type1
vfio_pci
kvm
kvm_intel
```

2. Next, need Ubuntu to load IOMMU properly. Edit `/etc/default/grub` and modify
"GRUB_CMDLINE_LINUX_DEFAULT", by adding "intel_iommu=on" to enable IOMMU. May also need to add
"vfio_iommu_type1.allow_unsafe_interrupts=1" if interrupt remapping should be enabled. Post these
changes, the GRUB command line should look like this:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on vfio_iommu_type1.allow_unsafe_interrupts=1
iommu=pt"
```

3. Enable the vfio-pci driver on boot:
```
$ echo vfio-pci | sudo tee /etc/modules-load.d/vfio-pci.conf
```

4. Run `sudo update-grub` to update GRUB with the new settings and reboot the system.

### Blacklist the GPU devices

We do not want the host running DGX Base OS to use the GPU Devices. Instead we want Guest VMs to get
full access to the NVIDIA GPU devices. Hence, in the DGX Base OS on the host,  blacklist them by
adding their IDs to the initramfs.

1. Run the command `lspci -nn | grep NVIDIA` to get the list of PCI-IDs
```
08:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
0a:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
10:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
11:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
12:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
18:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
1a:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
89:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
8b:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
92:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
94:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
```

2. Edit `/etc/modprobe.d/vfio.conf` and add this line:
```
options vfio-pci ids=10de:1db1,10de:1ac1
```

NOTE: First entry is for Volta and the latter for NVSwitch

3. Rebuild the initramfs by running sudo update-initramfs -u and reboot the system.

4. After the system reboots, verify GPU devices and NVSwitches are claimed by vfio_pci driver by
running `dmesg | grep vfio_pci`...
```
[   15.668150] vfio_pci: add [10de:1db1[ffff:ffff]] class 0x000000/00000000
[   15.736099] vfio_pci: add [10de:1ac1[ffff:ffff]] class 0x000000/00000000
```

```
$ lspci -nnk -d 10de:1ac1
10:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
	Kernel driver in use: vfio-pci
11:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
	Kernel driver in use: vfio-pci
12:00.0 Bridge [0680]: NVIDIA Corporation Device [10de:1ac1] (rev a1)
	Kernel driver in use: vfio-pci
```

If the `Kernel driver in use` is not `vfio-pci` and instead the nvidia driver, it may be necessary
to blacklist the nvidia driver or instruct it to load vfio-pci beforehand...

```
$ cat /etc/modprobe.d/nvidia.conf
softdep nvidia_384 pre: vfio-pci
```

One more check...

```
$ lspci -nnk -d 10de:1db1
08:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
0a:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
18:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
1a:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
89:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
8b:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
92:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
94:00.0 3D controller [0302]: NVIDIA Corporation Device [10de:1db1] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:1212]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia_vgpu_vfio, nvidia
```



