#!/usr/bin/env bash

. /etc/os-release
set -xe
# Get absolute path for script, and convenience vars for virtual and root
VIRT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SCRIPT_DIR="${VIRT_DIR}/scripts"

# Install Software
case "$ID_LIKE" in
    rhel*)
        # Install Vagrant

	# update yum
	sudo yum update

	# install essential packages and tools
	sudo yum -y install wget
	sudo yum group install -y "Development Tools"
	sudo yum install -y centos-release-qemu-ev qem-kvm-ev qemu-kvm libvirt virt-install bridge-utils libvirt-devel libxslt-devel libxml2-devel libvirt-devel libguestfs-tools-c

	# Optional set up networking for Vagrant VMs. Uncomment and adjust if needed
	#sudo echo "net.ipv4.ip_forward = 1"|sudo tee /etc/sysctl.d/99-ipforward.conf
	#sudo sysctl -p /etc/sysctl.d/99-ipforward.conf

	# start up libvirt as our VM method for Vagrant
	sudo usermod -a -G libvirt $(whoami)
	sudo systemctl enable libvirtd
	sudo systemctl start libvirtd

	# install vagrant (frozen at 2.2.3 to avoid various issues)
	pushd "$(mktemp -d)"
	wget https://releases.hashicorp.com/vagrant/2.2.3/vagrant_2.2.3_x86_64.rpm -O vagrant.rpm
	#sudo rpm -i vagrant.rpm
	sudo yum -y localinstall vagrant.rpm
	popd

	# install other dependencies
	sudo yum install -y sshpass

	# install kvm packages
	sudo yum install -y qemu-kvm libvirt-bin libvirt-dev bridge-utils libguestfs-tools
	sudo yum install -y qemu virt-manager firewalld OVMF

	# install vagrant plugins
	vagrant plugin install vagrant-hostmanager vagrant-libvirt
	vagrant plugin install vagrant-host-shell vagrant-scp vagrant-mutate

	#set up Vagrantfile and start up the configuration in Vagrant
	export DEEPOPS_VAGRANT_FILE="${VIRT_DIR}/Vagrantfile-centos"

	# End Install Vagrant
        ;;

    debian*)
        # Install Vagrant

	# update apt
	sudo apt update

	# install build-essential tools
	sudo apt install build-essential

	# install vagrant (frozen at 2.2.3 to avoid various issues)
	pushd "$(mktemp -d)"
	wget https://releases.hashicorp.com/vagrant/2.2.3/vagrant_2.2.3_x86_64.deb -O vagrant.deb
	sudo dpkg -i vagrant.deb
	popd

	# install other dependencies
	sudo apt install -y sshpass
	
	# install kvm packages
	sudo apt install -y qemu-kvm libvirt-bin libvirt-dev bridge-utils libguestfs-tools
	sudo apt install -y qemu ovmf virt-manager firewalld

	# install vagrant plugins
	vagrant plugin install vagrant-hostmanager vagrant-libvirt
	vagrant plugin install vagrant-host-shell vagrant-scp vagrant-mutate

	#set up Vagrantfile and start up the configuration in Vagrant
	export DEEPOPS_VAGRANT_FILE="${VIRT_DIR}/Vagrantfile-ubuntu"

	# End Install Vagrant
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        echo "You are on your own to install Vagrant and build a Vagrantfile then you can manually start the DeepOps virtual setup"
        ;;
esac

# Get absolute path for script, and convenience vars for virtual and root
VIRT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SCRIPT_DIR="${VIRT_DIR}/scripts"

#####################################
# Set up VMs for virtual cluster
#####################################

cp "${DEEPOPS_VAGRANT_FILE}" "${VIRT_DIR}/Vagrantfile"

# Create SSH key in default location if it doesn't exist
yes n | ssh-keygen -q -t rsa -f ~/.ssh/id_rsa -C "" -N "" || echo "key exists"

# Ensure we're in the right directory for Vagrant
cd "${VIRT_DIR}" || exit 1

# Make sure our environment is clean
vagrant global-status --prune

# Start vagrant via libvirt - set up the VMs
vagrant up --provider=libvirt

# Show the running VMs
virsh list

cd ..

# Install ansible and ansible-galaxy roles
./scripts/setup.sh

cd "${VIRT_DIR}" || exit 1
