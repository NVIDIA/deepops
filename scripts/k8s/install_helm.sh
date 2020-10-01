#!/usr/bin/env bash

set -x

HELM_INSTALL_DIR=/usr/local/bin
HELM_INSTALL_SCRIPT_URL="${HELM_INSTALL_SCRIPT_URL:-https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3}"

if ! kubectl version ; then
    echo "Unable to talk to Kubernetes API"
    exit 1
fi

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
    curl -fsSL -o /var/tmp/get_helm.sh "${HELM_INSTALL_SCRIPT_URL}"
    chmod +x /var/tmp/get_helm.sh
    #sed -i 's/sudo//g' /var/tmp/get_helm.sh
    mkdir -p ${HELM_INSTALL_DIR}
    HELM_INSTALL_DIR=${HELM_INSTALL_DIR} DESIRED_VERSION=v3.1.2 /var/tmp/get_helm.sh # Should match: config/group_vars/k8s-cluster.yml:helm_version:
fi

# Display the helm version for better debug
helm version
