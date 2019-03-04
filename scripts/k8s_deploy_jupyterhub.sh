#!/usr/bin/env bash

############
#helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
#helm update
#helm search jupyter
#openssl rand -hex 32
#kubectl create ns jh
#helm install jupyterhub/jupyterhub --name=jupyterhub --namespace=jh -f config/jupyterhub-config.yml
#helm upgrade jupyterhub jupyterhub/jupyterhub  --namespace=jh -f config/jupyterhub-config.yml
#kubectl -n jh logs -f hub-886fb9c58-bdfnr
#############
###

# Rook
kubectl get storageclass 2>&1 | grep "No resources found." >/dev/null 2>&1
if [ $? -eq 0 ] ; then
    echo "No storageclass found"
    echo "To provision Ceph storage, run: ./scripts/k8s_deploy_rook.sh"
    exit 1
fi

jhip=$(kubectl get nodes --no-headers -o custom-columns=:.status.addresses.*.address | cut -f1 -d, | head -1)
jhnp=$(kubectl -n kubeflow get svc jupyter-lb --no-headers -o custom-columns=:.spec.ports.*.nodePort)

echo
echo "Kubeflow app installed to: ${HOME}/${KFAPP}"
echo "To remove, run: cd ${HOME}/${KFAPP} && ${KUBEFLOW_SRC}/scripts/kfctl.sh delete k8s"
echo
echo "JupyterHub: http://${jhip}:${jhnp}"
echo
