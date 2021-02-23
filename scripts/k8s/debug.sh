#!/usr/bin/env bash
timestamp=$(date +%s)
logdir=config/log_${timestamp}
mkdir ${logdir}

# Provisioner configuration
cp config/inventory ${logdir}
git branch > ${logdir}/git-branch.log
git status > ${logdir}/git-status.log
git diff > ${logdir}/git-diff.log
git log --pretty=oneline | head -n 20 > ${logdir}/git-log.log

# GPU configuration
ansible kube-node -ba "nvidia-smi" -vv > ${logdir}/nvidia-smi.log

# Docker configuration
ansible kube-node -ba "docker info" -vv > ${logdir}/docker-info.log
ansible kube-node -ba "cat /etc/docker/daemon.json" -vv > ${logdir}/docker-daemon.log

# Kubectl
kubectl get pods -A > ${logdir}/get-pods.log
kubectl get daemonset -A > ${logdir}/get-daemons.log
kubectl get nodes > ${logdir}/get-nodes.log
kubectl describe nodes > ${logdir}/describe-nodes.log
for pod in $(kubectl get pods -n kube-system | grep nvidia-device-plugin | awk '{print $1}'); do
  kubectl -n kube-system logs ${pod} > ${logdir}/get-plugin-logs-${pod}.log
done

# Helm
helm list -aA > ${logdir}/helm-list.log

# Packaging
name="config/k8s-debug-${timestamp}.tgz"
tar -zcf ${name} ${logdir}
echo "A Kubernetes/Docker log bundle has been created at ${name}"
