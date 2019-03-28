#!/usr/bin/env bash

HELM_INSTALL_DIR=/usr/local/bin
HELM_INSTALL_SCRIPT_URL="${HELM_INSTALL_SCRIPT_URL:-https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get}"

# Install dependencies
. /etc/os-release
case "$ID_LIKE" in
    rhel*)
        type curl >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            sudo yum -y install curl
        fi
        ;;
    debian*)
        type curl >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            sudo apt -y install curl
        fi
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        exit 1
        ;;
esac

curl "${HELM_INSTALL_SCRIPT_URL}" > /tmp/get_helm.sh
chmod +x /tmp/get_helm.sh
#sed -i 's/sudo//g' /tmp/get_helm.sh
mkdir -p ${HELM_INSTALL_DIR}
HELM_INSTALL_DIR=${HELM_INSTALL_DIR} DESIRED_VERSION=v2.11.0 /tmp/get_helm.sh

/usr/local/bin/helm init --client-only
