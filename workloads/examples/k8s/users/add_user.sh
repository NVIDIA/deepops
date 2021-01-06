#!/usr/bin/env bash
user="${1}"

# generate user certs
openssl genrsa -out ${user}.key 2048
openssl req -new -key ${user}.key -out ${user}.csr -subj "/CN=${user}/O=example"
sudo openssl x509 -req -in ${user}.csr -CA /etc/kubernetes/ssl/ca.pem -CAkey /etc/kubernetes/ssl/ca-key.pem -CAcreateserial -out ${user}.crt -days 500

# create namespace and role binding for user
kubectl create ns ${user}
kubectl create rolebinding ${user}-binding --clusterrole=admin --user=${user} --namespace=${user}

# set up user config file
kubectl config --kubeconfig=./${user}.kubeconfig set-credentials ${user} --client-certificate=${user}.crt  --client-key=${user}.key --embed-certs=true
sudo kubectl config --kubeconfig=./${user}.kubeconfig set-cluster deepops --server=https://10.0.0.1:6443 --certificate-authority=/etc/kubernetes/ssl/ca.pem --embed-certs=true
kubectl config --kubeconfig=./${user}.kubeconfig set-context user --cluster=deepops --namespace=${user} --user=${user}
kubectl config --kubeconfig=./${user}.kubeconfig use-context user
