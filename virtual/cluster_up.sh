#!/bin/bash
set -ex

# start vagrant
vagrant up --no-parallel --provider=libvirt

cd ..

# Disable swap on mgmt servers (for Kubernetes)
ansible management -u root -e "ansible_user=root ansible_password=deepops" -b -a "swapoff -a"

# Deploy Kubernetes on mgmt
ansible-playbook -l management -v -b --flush-cache -e "@config/kube.yml" -e "ansible_user=root ansible_password=deepops" kubespray/cluster.yml

# Set up Kubernetes for remote administration
KUBECONFIG='./vagrant/admin.conf'
ansible management -u root -e "ansible_user=root ansible_password=deepops" -b -m fetch -a "src=/etc/kubernetes/admin.conf flat=yes dest=./vagrant/"
sed -i '/6443/c\    server: https:\/\/mgmt01:6443' ${KUBECONFIG}
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl && mv ./kubectl ./vagrant/kubectl

# Launch the apt repo service on k8s
KUBECONFIG=$KUBECONFIG ./vagrant/kubectl apply -f services/apt.yml

# Set up software
ansible-playbook -e "ansible_user=root ansible_password=deepops" -l login,dgx-servers --skip-tags skip-for-virtual ansible/playbooks/software.yml

# Install slurm
ansible-playbook -e "ansible_user=root ansible_password=deepops" -l slurm-cluster ansible/playbooks/slurm.yml
