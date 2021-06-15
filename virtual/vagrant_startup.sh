#!/usr/bin/env bash

. /etc/os-release
set -xe
# Get absolute path for script, and convenience vars for virtual and root
VIRT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# The default Vagrant Operating System is Ubuntu 18.04
# To override thise, change these variables to a supported OS
DEEPOPS_VAGRANT_OS=${DEEPOPS_VAGRANT_OS:-ubuntu}
DEEPOPS_OS_VERSION=${DEEPOPS_OS_VERSION:-18.04}

# Startup the specified VM OS, defaulting to Ubuntu

#####################################
# Install Vagrant and Dependencies
#####################################

case "$ID" in
  rhel*|centos*)
    # Install Vagrant & Dependencies for RHEL Systems

    export YUM_DEPENDENCIES="centos-release-qemu-ev qem-kvm-ev qemu-kvm libvirt virt-install \
      bridge-utils libvirt-devel libxslt-devel libxml2-devel libguestfs-tools-c sshpass qemu-kvm libvirt-bin \
      libvirt-dev bridge-utils libguestfs-tools qemu virt-manager firewalld OVMF"

    # shellcheck disable=SC2086
    if ! (yum grouplist installed | grep "Development Tools" && rpm -q $YUM_DEPENDENCIES) >/dev/null 2>&1; then
      echo "Installing yum dependencies..."

      sudo yum group install -y "Development Tools"
      # shellcheck disable=SC2086
      sudo yum install -y $YUM_DEPENDENCIES
    fi

    # Optional set up networking for Vagrant VMs. Uncomment and adjust if needed
    #sudo echo "net.ipv4.ip_forward = 1"|sudo tee /etc/sysctl.d/99-ipforward.conf
    #sudo sysctl -p /etc/sysctl.d/99-ipforward.conf

    # Ensure we have permissions to manage VMs
    export LIBVIRT_GROUP="libvirt"
    if ! groups "$(whoami)" | grep "${LIBVIRT_GROUP}"; then
      echo "Adding your user to ${LIBVIRT_GROUP} so you can manage VMs."
      echo "You may need to start a new shell to use vagrant interactively."
      sudo usermod -a -G libvirt "$(whoami)"
    fi

    # Ensure libvirtd is running
    if ! sudo systemctl is-active --quiet libvirtd; then
      sudo systemctl enable libvirtd
      sudo systemctl start libvirtd
    fi

    # Install Vagrant
    if ! which vagrant >/dev/null 2>&1; then
      # install vagrant (frozen at 2.2.3 to avoid various issues)
      pushd "$(mktemp -d)"
      wget https://releases.hashicorp.com/vagrant/2.2.14/vagrant_2.2.14_x86_64.rpm -O vagrant.rpm
      #sudo rpm -i vagrant.rpm
      sudo yum -y localinstall vagrant.rpm
      popd

      # install vagrant plugins
      vagrant plugin install vagrant-libvirt
      vagrant plugin install vagrant-host-shell vagrant-scp vagrant-mutate
    fi
    vagrant --version
    # End Install Vagrant & Dependencies for RHEL Systems
    ;;

  ubuntu*)
    # No interactive prompts from apt during this process
    export DEBIAN_FRONTEND=noninteractive
    # Install Vagrant & Dependencies for Debian Systems

    export APT_DEPENDENCIES="build-essential sshpass qemu-kvm libvirt-bin libvirt-dev bridge-utils \
      libguestfs-tools qemu ovmf virt-manager firewalld"

    # shellcheck disable=SC2086
    if ! (dpkg -s $APT_DEPENDENCIES) >/dev/null 2>&1; then
      echo "Installing apt dependencies..."

      # Update apt
      sudo apt-get update -y

      # Install build-essential tools
      # shellcheck disable=SC2086
      sudo apt-get install -y $APT_DEPENDENCIES
    fi

    # Ensure we have permissions to manage VMs
    case "${VERSION_ID}" in
      18.*)
        export LIBVIRT_GROUP="libvirt"
	;;
      *)
        export LIBVIRT_GROUP="libvirtd"
	;;
    esac
    if ! groups "$(whoami)" | grep "${LIBVIRT_GROUP}"; then
      echo "Adding your user to ${LIBVIRT_GROUP} so you can manage VMs."
      echo "You may need to start a new shell to use vagrant interactively."
      sudo usermod -a -G libvirt "$(whoami)"
    fi

    # Install Vagrant
    if ! which vagrant >/dev/null 2>&1; then
      # install vagrant (frozen at 2.2.3 to avoid various issues)
      pushd "$(mktemp -d)"
      wget https://releases.hashicorp.com/vagrant/2.2.14/vagrant_2.2.14_x86_64.deb -O vagrant.deb
      sudo dpkg -i vagrant.deb
      popd
  
      # install vagrant plugins
      vagrant plugin install vagrant-libvirt
      vagrant plugin install vagrant-host-shell vagrant-scp vagrant-mutate
    fi
    vagrant --version
    # End Install Vagrant & Dependencies for Debian Systems
    ;;
  *)
    echo "Unsupported Operating System $ID_LIKE"
    echo "You are on your own to install Vagrant and build a Vagrantfile then you can manually start the DeepOps virtual setup"
    ;;
esac

#####################################
# Set up VMs for virtual cluster
#####################################
# Set up Vagrantfile and start up the configuration in Vagrant
if [ ${DEEPOPS_FULL_INSTALL} ]; then
  export CENTOS_DEEPOPS_VAGRANT_FILE="${DEEPOPS_VAGRANT_FILE:-${VIRT_DIR}/Vagrantfile-centos${DEEPOPS_OS_VERSION}-full}"
  export UBUNTU_DEEPOPS_VAGRANT_FILE="${DEEPOPS_VAGRANT_FILE:-${VIRT_DIR}/Vagrantfile-ubuntu${DEEPOPS_OS_VERSION}-full}"
else
  export CENTOS_DEEPOPS_VAGRANT_FILE="${DEEPOPS_VAGRANT_FILE:-${VIRT_DIR}/Vagrantfile-centos${DEEPOPS_OS_VERSION}}"
  export UBUNTU_DEEPOPS_VAGRANT_FILE="${DEEPOPS_VAGRANT_FILE:-${VIRT_DIR}/Vagrantfile-ubuntu${DEEPOPS_OS_VERSION}}"
fi

if [ ${DEEPOPS_VAGRANT_OS} = "centos" ]; then
  export DEEPOPS_VAGRANT_FILE=${CENTOS_DEEPOPS_VAGRANT_FILE}
else
  export DEEPOPS_VAGRANT_FILE=${UBUNTU_DEEPOPS_VAGRANT_FILE}
fi

cp "${DEEPOPS_VAGRANT_FILE}" "${VIRT_DIR}/Vagrantfile"

# Create SSH key in default location if it doesn't exist
yes n | ssh-keygen -q -t rsa -f ~/.ssh/id_rsa -C "" -N "" || echo "key exists"

# Ensure we're in the right directory for Vagrant
cd "${VIRT_DIR}" || exit 1

# Ensure we're using the libvirt group during vagrant up
newgrp "${LIBVIRT_GROUP}" << MAKE_VMS
  # Make sure our environment is clean
  vagrant global-status --prune

  # Start vagrant via libvirt - set up the VMs
  set -e
  vagrant up --provider=libvirt

  # Show the running VMs
  virsh list
MAKE_VMS
