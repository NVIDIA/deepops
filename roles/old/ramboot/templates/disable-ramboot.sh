#!/bin/bash
KERNELVERSION=`uname -r`
mkdir /tmp/sda
mount /dev/nvme0n1p1 /tmp/sda
rm /tmp/sda/boot/initrd.img-$KERNELVERSION-ramboot
rm /tmp/sda/boot/vmlinuz-$KERNELVERSION-ramboot
mv /tmp/sda/boot/grub/grub.cfg.notramboot /tmp/sda/boot/grub/grub.cfg
umount /tmp/sda
