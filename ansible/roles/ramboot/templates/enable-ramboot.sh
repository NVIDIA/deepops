#!/bin/bash
KERNELVERSION=`uname -r`
sed -i '/UUID/s/^/#/g' /etc/fstab 
echo "none / tmpfs defaults 0 0" >> /etc/fstab
mkinitramfs -o /boot/initrd.img-$KERNELVERSION-ramboot
ln -s /boot/vmlinuz-$KERNELVERSION /boot/vmlinuz-$KERNELVERSION-ramboot
update-grub
