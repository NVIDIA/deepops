#!/usr/bin/env bash

set -x

HELM_INSTALL_DIR=/usr/local/bin
HELM_INSTALL_SCRIPT_URL="${HELM_INSTALL_SCRIPT_URL:-https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get}"

if ! kubectl version ; then
    echo "Unable to talk to Kubernetes API"
    exit 1
fi

# un-taint master nodes so they'll run the tiller pod
kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- >/dev/null 2>&1

# wait for tiller pod
kubectl -n kube-system wait --for=condition=Ready -l app=helm,name=tiller --timeout=90s pod

# Install dependencies
. /etc/os-release
case "$ID" in
    rhel*|centos*)
        if ! type curl >/dev/null 2>&1 ; then
            sudo yum -y install curl
        fi
        ;;
    ubuntu*)
        if ! type curl >/dev/null 2>&1 ; then
            sudo apt-get -y install curl
        fi
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        exit 1
        ;;
esac

if ! type helm >/dev/null 2>&1 ; then
    curl "${HELM_INSTALL_SCRIPT_URL}" > /tmp/get_helm.sh
    chmod +x /tmp/get_helm.sh
    #sed -i 's/sudo//g' /tmp/get_helm.sh
    mkdir -p ${HELM_INSTALL_DIR}
    HELM_INSTALL_DIR=${HELM_INSTALL_DIR} DESIRED_VERSION=v2.14.3 /tmp/get_helm.sh
fi

# We need to dynamically set up Helm args, so let's use an array
helm_init_args=("--client-only")
if [ "${DEEPOPS_HELM_REPO}" ]; then
	helm_init_args+=("--stable-repo-url" "${DEEPOPS_HELM_REPO}")
fi

if type helm >/dev/null 2>&1 ; then
    helm init "${helm_init_args[@]}"
    helm repo update
else
    echo "Helm client not installed"
    exit 1
fi
