#!/usr/bin/env bash

export KS_VER=0.13.1
export KS_PKG=ks_${KS_VER}_linux_amd64
export KS_INSTALL_DIR=/usr/local/bin

export KUBEFLOW_TAG=v0.5.1
export KFAPP=kubeflow
export KUBEFLOW_SRC=/opt/kubeflow

export DEEPOPS_DIR=$(dirname $(dirname  $(readlink -f $0)))

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
            sudo apt-get -y install curl wget
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

# Get master ip
master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)

# Check for ingress controller
ingress_name="nginx-ingress"
ingress_ip_string="$(echo ${master_ip} | tr '.' '-')"
if kubectl describe service -l "app=${ingress_name},component=controller" | grep 'LoadBalancer Ingress' >/dev/null 2>&1; then
    lb_ip="$(kubectl describe service -l "app=${ingress_name},component=controller" | grep 'LoadBalancer Ingress' | awk '{print $3}')"
    ingress_ip_string="$(echo ${lb_ip} | tr '.' '-').nip.io"
    echo "Using load balancer url: ${ingress_ip_string}"
fi

# Initialize and generate kubeflow
set -e # XXX: Fail if anything in the initialization or configuration fail
pushd ${HOME}
${KUBEFLOW_SRC}/scripts/kfctl.sh init ${KFAPP} --platform none
cd ${KFAPP}

# Update the Kubeflow Jupyter UI
export KSAPP_DIR="$(pwd)/ks_app"
export KUBEFLOW_SRC
${DEEPOPS_DIR}/scripts/update_kubeflow_config.py

${KUBEFLOW_SRC}/scripts/kfctl.sh generate k8s
pushd ${KSAPP_DIR}
set +e

# NOTE: temporarily using a custom image, to add custom command functionality
ks param set jupyter-web-app image deepops/kubeflow-jupyter-web-app:v0.5-custom-command

# Use NodePort directly if the IP string uses the master IP, otherwise use Ingress URL
if echo "${ingress_ip_string}" | grep "${master_ip}" >/dev/null 2>&1; then
    ks param set ambassador ambassadorServiceType NodePort
    popd
    ${KUBEFLOW_SRC}/scripts/kfctl.sh apply k8s
    popd
    kf_ip=$master_ip
    kf_port=$(kubectl -n kubeflow get svc ambassador --no-headers -o custom-columns=:.spec.ports.*.nodePort)
    kf_url="http://${kf_ip}:${kf_port}"
else
    ks param set ambassador ambassadorServiceType LoadBalancer
    popd
    ${KUBEFLOW_SRC}/scripts/kfctl.sh apply k8s
    popd
    kf_ip=$(kubectl -n kubeflow get svc ambassador --no-headers -o custom-columns=:.status.loadBalancer.ingress[0].ip)
    kf_url="http://${kf_ip}"
fi

echo
echo "Kubeflow app installed to: ${HOME}/${KFAPP}"
echo "To remove, run: cd ${HOME}/${KFAPP} && ${KUBEFLOW_SRC}/scripts/kfctl.sh delete k8s"
echo "To fully remove all source and application code run: cd ${HOME} && rm -rf ${KFAPP}; rm -rf ${KUBEFLOW_SRC}"
echo "To fully remove everything: cd ${HOME}/${KFAPP} && ${KUBEFLOW_SRC}/scripts/kfctl.sh delete k8s; cd ${DEEPOPS_DIR} && sudo rm -rf ${KFAPP}; sudo rm -rf ${KUBEFLOW_SRC}"
echo
echo "Kubeflow Dashboard: ${kf_url}"
echo
echo "This script is deprecated and will be removed in a future release in favor of v0.6"
