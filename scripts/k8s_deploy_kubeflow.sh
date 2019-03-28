#!/usr/bin/env bash

export KS_VER=0.13.1
export KS_PKG=ks_${KS_VER}_linux_amd64
export KS_INSTALL_DIR=/usr/local/bin

export KUBEFLOW_TAG=v0.4.1
export KFAPP=kubeflow
export KUBEFLOW_SRC=/opt/kubeflow

KSONNET_URL="${KSONNET_URL:-https://github.com/ksonnet/ksonnet/releases/download/v${KS_VER}/${KS_PKG}.tar.gz}"
KUBEFLOW_URL="${KUBEFLOW_URL:-https://raw.githubusercontent.com/kubeflow/kubeflow/${KUBEFLOW_TAG}/scripts/download.sh}"

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

# Ksonnet
wget -O /tmp/${KS_PKG}.tar.gz "${KSONNET_URL}" \
      --no-check-certificate
mkdir -p ${KS_INSTALL_DIR}
tempd=$(mktemp -d)
tar -xvf /tmp/${KS_PKG}.tar.gz -C ${tempd}
sudo mv ${tempd}/${KS_PKG}/ks ${KS_INSTALL_DIR}
rm -rf ${tempd} /tmp/${KS_PKG}.tar.gz

# Kubeflow
if [ ! -d ${KUBEFLOW_SRC} ] ; then
    tempd=$(mktemp -d)
    cd ${tempd}
    curl "${KUBEFLOW_URL}" | bash
    cd -
    sudo mv ${tempd} ${KUBEFLOW_SRC}
fi

pushd ${HOME}
${KUBEFLOW_SRC}/scripts/kfctl.sh init ${KFAPP} --platform none
cd ${KFAPP}
${KUBEFLOW_SRC}/scripts/kfctl.sh generate k8s
pushd ks_app
ks param set jupyter serviceType NodePort
popd
${KUBEFLOW_SRC}/scripts/kfctl.sh apply k8s
popd

jhip=$(kubectl get nodes --no-headers -o custom-columns=:.status.addresses.*.address -l node-role.kubernetes.io/master= | cut -f1 -d, | head -1)
jhnp=$(kubectl -n kubeflow get svc jupyter-lb --no-headers -o custom-columns=:.spec.ports.*.nodePort)

echo
echo "Kubeflow app installed to: ${HOME}/${KFAPP}"
echo "To remove, run: cd ${HOME}/${KFAPP} && ${KUBEFLOW_SRC}/scripts/kfctl.sh delete k8s"
echo
echo "JupyterHub: http://${jhip}:${jhnp}"
echo
