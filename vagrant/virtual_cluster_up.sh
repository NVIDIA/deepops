#!/bin/bash
set -x

# TODO: include vagrant install, ansible etc
vagrant up --no-parallel
#sudo pip install netaddr

cd ..

# Disable swap on mgmt servers (for Kubernetes)
ansible mgmt -u root -e "ansible_user=root ansible_password=deepops" -b -a "swapoff -a"

# Deploy Kubernetes on mgmt
ansible-playbook -l mgmt -v -b --flush-cache -e "@config/kube.yml" -e "ansible_user=root ansible_password=deepops" kubespray/cluster.yml

# Set up Kubernetes for remote administration
KUBECONFIG='./vagrant/admin.conf'
ansible mgmt -u root -e "ansible_user=root ansible_password=deepops" -b -m fetch -a "src=/etc/kubernetes/admin.conf flat=yes dest=./vagrant/"
sed -i '/6443/c\    server: https:\/\/mgmt01:6443' ${KUBECONFIG}
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl && mv ./kubectl ./vagrant/kubectl

# Set up Helm
#scripts/helm_install_linux.sh
##KUBECONFIG=$KUBECONFIG ./vagrant/kubectl create sa tiller --namespace kube-system
##KUBECONFIG=$KUBECONFIG ./vagrant/kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
##KUBECONFIG=$KUBECONFIG helm init --service-account tiller --node-selectors node-role.kubernetes.io/master=true

# Set up Ceph
#KUBECONFIG=$KUBECONFIG helm repo add rook-master https://charts.rook.io/master
#KUBECONFIG=$KUBECONFIG helm install --namespace rook-ceph-system --name rook-ceph rook-master/rook-ceph --version v0.7.0-284.g863c10f --set agent.flexVolumeDirPath=/var/lib/kubelet/volume-plugins/
#KUBECONFIG=$KUBECONFIG ./vagrant/kubectl create -f services/rook-cluster.yml

# Show Ceph status
#KUBECONFIG=$KUBECONFIG ./vagrant/kubectl -n rook-ceph exec -ti rook-ceph-tools ceph status

# Install the ingress controller
#KUBECONFIG=$KUBECONFIG helm install --values config/ingress.yml stable/nginx-ingress
#KUBECONFIG=$KUBECONFIG ./vagrant/kubectl logs -l app=nginx-ingress

# Launch the apt repo service on k8s
KUBECONFIG=$KUBECONFIG ./vagrant/kubectl apply -f services/apt.yml

# Set up software
ansible-playbook -e "ansible_user=root ansible_password=deepops" -l login,dgx-servers --skip-tags skip-for-virtual ansible/playbooks/software.yml

# Install slurm
ansible-playbook -e "ansible_user=root ansible_password=deepops" -l slurm-cluster ansible/playbooks/slurm.yml
