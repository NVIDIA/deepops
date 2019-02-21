#!/bin/bash
set -ex

# Start vagrant via libvirt - set up the VMs
vagrant up --no-parallel --provider=libvirt

# Show the running VMs
virsh list

cd ..

# Create the config for deepops servers (and use the virtual inventory)
cp -r config.example/ config/
cp virtual/virtual_inventory config/inventory
# Make sure to use the `vagrant` user instead of `ubuntu`
sed -i 's/ansible_user: ubuntu/ansible_user: vagrant/g' config/group_vars/all.yml 

# Bootstrap the VMs so that they can be accessible with the rest of the ansible playbooks without
# needing a password
ansible-playbook -T 30 -e "ansible_user=vagrant ansible_password=vagrant" --skip-tags skip-for-virtual playbooks/bootstrap-ansible.yml
ansible-playbook -T 30 -e "ansible_user=vagrant ansible_password=vagrant" --skip-tags skip-for-virtual playbooks/bootstrap.yml

# Deploy Kubernetes on mgmt
ansible-playbook -l management -v -b --flush-cache -e "@config/kube.yml" kubespray/cluster.yml

# Set up Kubernetes for remote administration
KUBECONFIG='./virtual/admin.conf'
ansible management -e "ansible_user=vagrant" -b -m fetch -a "src=/etc/kubernetes/admin.conf flat=yes dest=./virtual/"
sed -i '/6443/c\    server: https:\/\/mgmt:6443' ${KUBECONFIG}
#cp ./virtual/admin.conf ~/.kube/config
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl && mv ./kubectl ./virtual/kubectl

export KUBECONFIG=$KUBECONFIG

# Initialize helm
helm init
sleep 15

# Set up ceph for persistent storage
helm repo add rook-master https://charts.rook.io/master
helm install --namespace rook-ceph-system --name rook-ceph rook-master/rook-ceph --version v0.9.0-79.g1a1ffdd
./virtual/kubectl create -f services/rook-cluster.yml

# Install the ingress controller
helm install --values config/ingress.yml stable/nginx-ingress

# NOTE: at this point, on a real cluster, it would be time to set up DGXie
# for DHCP, DNS, and PXE

# Launch the apt repo service on k8s
./virtual/kubectl apply -f services/apt.yml

# Launch the container registry
helm repo add stable https://kubernetes-charts.storage.googleapis.com
helm install --values config/registry.yml stable/docker-registry --version 1.4.3

# Install nvidia drivers on dgx-servers
ansible-playbook -l dgx-servers -e "ansible_user=vagrant" playbooks/nvidia-driver.yml

# Set up software
#ansible-playbook -e "ansible_user=vagrant" -l login,dgx-servers --skip-tags skip-for-virtual ansible/playbooks/software.yml

# Install slurm
#ansible-playbook -e "ansible_user=vagrant" -l slurm-cluster playbooks/slurm.yml



