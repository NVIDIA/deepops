#!/usr/bin/env bash

export KUBEFLOW_TAG=v0.5.0
export KFAPP=kubeflow
export KUBEFLOW_SRC=/opt/kubeflow

KUBEFLOW_URL="${KUBEFLOW_URL:-https://github.com/kubeflow/kubeflow/releases/download/v0.5.0/kfctl_${KUBEFLOW_TAG}_linux.tar.gz}"

###

# Install dependencies
. /etc/os-release
case "$ID_LIKE" in
    rhel*)
        type curl >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            sudo yum -y install curl wget
        fi
        ;;
    debian*)
        type curl >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            sudo apt -y install curl wget
        fi
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        exit 1
        ;;
esac

# Rook
kubectl get storageclass 2>&1 | grep "No resources found." >/dev/null 2>&1
if [ $? -eq 0 ] ; then
    echo "No storageclass found"
    echo "To provision Ceph storage, run: ./scripts/k8s_deploy_rook.sh"
    exit 1
fi

# Kubeflow
if [ ! -d ${KUBEFLOW_SRC} ] ; then
    echo ${KUBEFLOW_URL}
    tempd=$(mktemp -d)
    cd ${tempd}
    wget ${KUBEFLOW_URL}
    tar -xvf "kfctl_${KUBEFLOW_TAG}_linux.tar.gz"
    cd -
    sudo mv ${tempd} ${KUBEFLOW_SRC}
fi

pushd ${HOME}
${KUBEFLOW_SRC}/kfctl init ${KFAPP}
cd ${KFAPP}
${KUBEFLOW_SRC}/kfctl generate all
${KUBEFLOW_SRC}/kfctl apply all

kfip=$(kubectl get nodes --no-headers -o custom-columns=:.status.addresses.*.address -l node-role.kubernetes.io/master= | cut -f1 -d, | head -1)
kfnp=$(kubectl -n kubeflow get svc ambassador --no-headers -o custom-columns=:.spec.ports.*.nodePort)

echo
echo "Kubeflow app installed to: ${HOME}/${KFAPP}"
echo "To remove, run: cd ${HOME}/${KFAPP} && ${KUBEFLOW_SRC}/kfctl delete all --delete_storage"
echo
echo "Kubeflow Ambassador: http://${kfip}:${kfnp}"
echo
