#!/bin/bash

pwd
cd virtual || exit 1

K8S_CONFIG_DIR=$(pwd)/config
export KUBECONFIG="${K8S_CONFIG_DIR}/artifacts/admin.conf"
export PATH="${K8S_CONFIG_DIR}/artifacts:${PATH}"

chmod 755 "$K8S_CONFIG_DIR/artifacts/kubectl"
kubectl get nodes
kubectl run gpu-test --rm -t -i --restart=Never --image=nvidia/cuda --limits=nvidia.com/gpu=1 -- nvidia-smi
