# Configure compute nodes to have (stateless) rootfs in ram

Configures compute nodes to, on subsequent boots, read their root filesystem from /dev/sda2 entirely into ram. 

This is useful for enabling user modifications to the root file system.  
For example, a user installs a beta driver.  At reboot, all user changes to the rootfs are lost and the nodes will be reverted back to a known state.

When running in this mode one should ensure that only essential software is installed on /dev/sda2.  Everything that is on /dev/sda2 will consume space in ram.  

## To configure, set ansible variables
- is_compute yes
- is_stateless yes

# Configure compute nodes to have normal disk based rootfs

If compute nodes are running in stateless mode you are not able to simply makes changes to the persistant data on the rootfs disk.
For example, you want to install a new driver on all of the compute nodes. 

To make changes, you have two options
- Mount /dev/sda2 somewhere, make changes, reboot.
- Boot from disk, not ramdisk. You can either:
  - Choose non-ramdisk from grub boot menu
     - Using console access or modify /boot/grub/grub.cfg as stored on /dev/sda2.
  - Remove ramdisk option
     - Re-run ansible play using the variables below. 

## To unconfigure, set ansible variables
- is_compute yes
- is_stateless no