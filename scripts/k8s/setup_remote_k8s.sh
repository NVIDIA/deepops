#!/usr/bin/env bash

# Source common libraries and env variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."
source ${ROOT_DIR}/scripts/common.sh

KUBECTL_BINARY_URL="${KUBECTL_BINARY_URL:-https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl}"

# Install dependencies
. /etc/os-release
case "$ID" in
    rhel*|centos*)
        type curl >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            sudo yum -y install curl
        fi
        ;;
    ubuntu*)
        type curl >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            sudo apt-get -y install curl
        fi
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        exit 1
        ;;
esac

# Grab kubernetes admin config file from kubernetes nodes
ansible gpu-servers -b -m fetch -a "src=/etc/kubernetes/admin.conf flat=yes dest=./"

# Grab kubectl binary
curl -LO "${KUBECTL_BINARY_URL}"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin

# Merge or copy kubernetes config file
mkdir -p ~/.kube
KUBECONFIG=./admin.conf
if [ -f ~/.kube/config ] ; then
    mv ~/.kube/config{,.bak}
    KUBECONFIG=${KUBECONFIG}:~/.kube/config.bak 
fi
KUBECONFIG=${KUBECONFIG} kubectl config view --flatten | tee ~/.kube/config
rm ./admin.conf
