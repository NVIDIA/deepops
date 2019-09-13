#!/usr/bin/env bash

export KFAPP=~/kubeflow
export KFCTL=~/kfctl
export KUBEFLOW_TAG=v0.6.2
export KFCTL_URL=https://github.com/kubeflow/kubeflow/releases/download/${KUBEFLOW_TAG}/kfctl_${KUBEFLOW_TAG}_linux.tar.gz
export CONFIG="https://raw.githubusercontent.com/kubeflow/kubeflow/v0.6-branch/bootstrap/config/kfctl_existing_arrikto.0.6.2.yaml"
export CONFIG="https://raw.githubusercontent.com/kubeflow/kubeflow/v0.6-branch/bootstrap/config/kfctl_k8s_istio.0.6.2.yaml"


# Specify credentials for the default user.
export KUBEFLOW_USER_EMAIL="admin@kubeflow.org"
export KUBEFLOW_PASSWORD="12341234"

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

# Download the kfctl binary and move it to the default location
pushd .
mkdir /tmp/kf-download
cd /tmp/kf-download
curl -O -L ${KFCTL_URL}
tar -xvf kfctl_${KUBEFLOW_TAG}_linux.tar.gz
mv kfctl ${KFCTL}
popd
rm -rf /tmp/kf-download

# Initialize and apply the Kubeflow project using the specified config
${KFCTL} init ${KFAPP} --config=${CONFIG} -V
cd ${KFAPP}
${KFCTL} generate all -V
${KFCTL} apply all -V

# Get LoadBalancer and NodePorts
master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)
nodePort="$(kubectl get svc -n istio-system istio-ingressgateway --no-headers -o custom-columns=PORT:.spec.ports[2].nodePort)
lb_ip="$(kubectl get svc -n istio-system istio-ingressgateway --no-headers -o -o custom-columns=:.status.loadBalancer.ingress[0].ip)
kf_url="http://${master_ip}:${nodePort}"

echo
echo "Kubeflow app installed to: ${KFAPP}"
echo "To remove, run: cd ${KFAPP} && ${KFCTL} delete k8s"
echo "To fully remove all source and application code run: cd ${HOME} && rm -rf ${KFAPP}; rm ${KFCTL}"
echo "To fully remove everything:"
echo "cd ${KFAPP} && ${KFCTL} delete k8s; cd && sudo rm -rf ${KFAPP}; sudo rm ${KFCTL}"
echo 
echo "Kubeflow Dashboard: ${kf_url}"
echo ${lb_ip}
echo 
