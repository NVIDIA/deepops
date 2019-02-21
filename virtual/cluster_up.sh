#!/bin/bash
set -x

# Start vagrant via libvirt - set up the VMs
vagrant up --no-parallel --provider=libvirt

cd ..

# Bootstrap the VMs so that they can be accessible with the rest of the ansible playbooks without
# needing a password
ansible-playbook -T 30 -e "ansible_user=vagrant ansible_password=vagrant" --skip-tags skip-for-virtual playbooks/bootstrap-ansible.yml
ansible-playbook -T 30 -e "ansible_user=vagrant ansible_password=vagrant" --skip-tags skip-for-virtual playbooks/bootstrap.yml

# Disable swap on mgmt servers (for Kubernetes)
ansible management -e "ansible_user=vagrant" -b -a "swapoff -a"

# Deploy Kubernetes on mgmt
ansible-playbook -l management -v -b --flush-cache -e "@config/kube.yml" -e "ansible_user=vagrant" kubespray/cluster.yml

# Set up Kubernetes for remote administration
KUBECONFIG='./virtual/admin.conf'
ansible management -e "ansible_user=vagrant" -b -m fetch -a "src=/etc/kubernetes/admin.conf flat=yes dest=./virtual/"
sed -i '/6443/c\    server: https:\/\/mgmt:6443' ${KUBECONFIG}
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl && mv ./kubectl ./virtual/kubectl

# Launch the apt repo service on k8s
KUBECONFIG=$KUBECONFIG ./virtual/kubectl apply -f services/apt.yml

# Set up software
#ansible-playbook -e "ansible_user=vagrant" -l login,dgx-servers --skip-tags skip-for-virtual ansible/playbooks/software.yml

# Install slurm
#ansible-playbook -e "ansible_user=vagrant" -l slurm-cluster playbooks/slurm.yml



