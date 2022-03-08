#!/usr/bin/env bash
# This is a basic debug script for Kubernetes clusters
# Please use this script to collect a log bundle when opening a support request or asking for debug assistance

# Ideally this is run out of the DeepOps repo used to deploy the cluster
# However, this script will also work best-effort for any K8s cluster, DeepOps or otherwise
# Requirements for this script are a working "kubectl" and ideally a working "helm"
# Optionally, a working "ansible" with a config/inventory file that has kubernetes node defined in a kube-node group

# Source common libraries and env variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."
source ${ROOT_DIR}/scripts/common.sh

timestamp=$(date +%s)
logdir=config/log_${timestamp}
mkdir -p ${logdir}

# Provisioner configuration (specific to DeepOps deployments)
cp config/inventory ${logdir}
git branch > ${logdir}/git-branch.log
git status > ${logdir}/git-status.log
git diff > ${logdir}/git-diff.log
git log --pretty=oneline | head -n 20 > ${logdir}/git-log.log

# GPU configuration
ansible kube-node -ba "nvidia-smi" -vv > ${logdir}/nvidia-smi.log
ansible kube-node -ba "cat /etc/nvidia/gridd.conf" -vv > ${logdir}/vgpu-gridd.conf.log

# Docker configuration
ansible kube-node -ba "docker info" -vv > ${logdir}/docker-info.log
ansible kube-node -ba "cat /etc/docker/daemon.json" -vv > ${logdir}/docker-daemon.log

# Kubectl (Generic for any Kubernetes cluster)
kubectl get pvc -A > ${logdir}/get-pvc.log
kubectl get pv -A > ${logdir}/get-pv.log
kubectl get pods -A > ${logdir}/get-pods.log
kubectl get daemonset -A > ${logdir}/get-daemons.log
kubectl get nodes > ${logdir}/get-nodes.log
kubectl describe nodes > ${logdir}/describe-nodes.log
kubectl get storageclass > ${logdir}/get-storageclass.log
kubectl get events -A > ${logdir}/get-events.log
kubectl get svc -A > ${logdir}/get-svc.log

# Kubectl / GPU Operator (Generic for any Kubernetes cluster)
kubectl get pvc -A > ${logdir}/get-pvc.log
for pod in $(kubectl get pods -n gpu-operator-resources  | grep nvidia-device-plugin | awk '{print $1}'); do
  kubectl -n gpu-operator-resources  logs ${pod} > ${logdir}/get-plugin-logs-${pod}.log
done
for pod in $(kubectl get pods -n gpu-operator-resources  | grep gpu-feature-discovery | awk '{print $1}'); do
  kubectl -n gpu-operator-resources  logs ${pod} > ${logdir}/get-plugin-logs-${pod}.log
done
for pod in $(kubectl get pods -n gpu-operator-resources  | grep nvidia-operator-validator | awk '{print $1}'); do
  kubectl -n gpu-operator-resources  logs ${pod} > ${logdir}/get-plugin-logs-${pod}.log
done
for pod in $(kubectl get pods -n gpu-operator-resources  | grep driver | awk '{print $1}'); do
  kubectl -n gpu-operator-resources  logs ${pod} > ${logdir}/get-plugin-logs-${pod}.log
done
for pod in $(kubectl get pods -n gpu-operator-resources  | grep mig | awk '{print $1}'); do
  kubectl -n gpu-operator-resources  logs ${pod} > ${logdir}/get-plugin-logs-${pod}.log
done
kubectl describe pods -n gpu-operator-resources > ${logdir}/describe-gpu-operator-resources-pods.log
kubectl describe configmap -n gpu-operator-resources default-mig-parted-config > ${logdir}/default-mig-parted-config.log


# Helm
helm list -aA > ${logdir}/helm-list.log

# DCGM example output / metrics
# Collect metrics from all nodes for debug
ansible kube-node -vv -bm raw -a "curl http://127.0.0.1:9400/metrics" > ${logdir}/dcgm-metrics.log

# Packaging
name="config/k8s-debug-${timestamp}.tgz"
tar -zcf ${name} ${logdir}
echo "A Kubernetes/Docker log bundle has been created at ${name}"
