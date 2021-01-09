#!/usr/bin/env bash

# Upgrading:
# `helm update`
# `helm search rook` # get latest version number
# `helm upgrade --namespace rook-ceph rook-ceph rook-release/rook-ceph --version v0.9.0-174.g3b14e51`

# Get absolute path for script and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."
CHART_VERSION="1.22.1"

HELM_ROOK_CHART_REPO="${HELM_ROOK_CHART_REPO:-https://charts.rook.io/release}"
HELM_ROOK_CHART_VERSION="${HELM_ROOK_CHART_VERSION:-v1.1.1}"

# Allow overriding config dir to look in
DEEPOPS_CONFIG_DIR=${DEEPOPS_CONFIG_DIR:-"${ROOT_DIR}/config"}

# Default creds to create
DEEPOPS_ROOK_USER="${DEEPOPS_ROOK_USER:-admin}"
DEEPOPS_ROOK_PASS="${DEEPOPS_ROOK_PASS:-deepops}"

# Setting to set Rook as default or non-default storageclass
DEEPOPS_ROOK_SC_NAME="${DEEPOPS_ROOK_SC_NAME:-rook-ceph-block}"
DEEPOPS_ROOK_NO_DEFAULT="${DEEPOPS_ROOK_NO_DEFAULT:-}"

if [ ! -d "${DEEPOPS_CONFIG_DIR}" ]; then
    echo "Can't find configuration in ${DEEPOPS_CONFIG_DIR}"
    echo "Please set DEEPOPS_CONFIG_DIR env variable to point to config location"
    exit 1
fi


function help_me() {
  echo "Usage:"
  echo "-h    This message."
  echo "-p    Print out the connection info for Rook-Ceph."
  echo "-d    Delete Rook from your system (this delete any created volumes)."
  echo "-w    Poll for rook-ceph to reach a healthy and initialized state."
  echo "-u    Create a new dashboard user (default username: 'admin' password: 'deepops', set with env variables DEEPOPS_ROOK_USER/DEEPOPS_ROOK_PASS)."
  echo "-x    Install Rook-Ceph, but do not set it as the Default StorageClass."
}


function poll_ceph() {
  echo "Beginning to poll for Ceph and Rook setup completion."
  echo "This may throw several errors and take up to 10 minutes. This behavior is expected."
  echo "The script will stop polling when Ceph setup is completed and the cluster is in a healthy state".
  echo ""; echo ""; echo ""

  while true; do
    rook_tools_pod=$(kubectl -n rook-ceph get pod -l app=rook-ceph-tools -o name | cut -d \/ -f2 | sed -e 's/\\r$//g')
    kubectl -n rook-ceph exec -ti $rook_tools_pod -- ceph status # Run once to print output
    kubectl -n rook-ceph exec -ti $rook_tools_pod -- ceph status | grep "mds: cephfs" | grep "up:active" | grep "standby-replay" # Run again to check for completion
    if [ "${?}" == "0" ]; then
      echo "Ceph has completed setup."
      break
    fi
    sleep 15
  done
}


function delete_rook() {
  kubectl delete -f workloads/services/k8s/rook-cluster.yml
  helm delete rook-ceph
  kubectl -n rook-ceph delete cephcluster rook-ceph
  kubectl -n rook-ceph delete storageclass rook-ceph-block
  kubectl delete ns rook-ceph-system
  kubectl delete ns rook-ceph
  ansible k8s-cluster -b -m file -a "path=/var/lib/rook state=absent"
}


function print_rook() {
  # Get Rook Ceph Tools POD name
  export rook_toolspod=$(kubectl -n rook-ceph get pod -l app=rook-ceph-tools --no-headers -o custom-columns=:.metadata.name)

  # Get IP of first master
  master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)

  # Get Ceph dashboard port
  dash_port=$(kubectl -n rook-ceph get svc rook-ceph-mgr-dashboard-external-https --no-headers -o custom-columns=PORT:.spec.ports.*.nodePort)

  # Ceph Dashboard
  export rook_ceph_dashboard="https://${master_ip}:${dash_port}"

  echo
  echo "Ceph deployed, it may take up to 10 minutes for storage to be ready"
  echo "If install takes more than 30 minutes be sure you have cleaned up any previous Rook installs by running '${0} -d' and have installed the required libraries using the bootstrap-rook.yml playbook"
  echo "Monitor readiness with: ${0} -w"
  echo

  echo "Ceph dashboard: ${rook_ceph_dashboard}"
  echo
  echo "Create dashboard user with: kubectl -n rook-ceph exec -ti ${rook_toolspod} -- ceph dashboard set-login-credentials <username> <password>"
  echo
}


function create_ceph_user() {
  # Get Rook Ceph Tools POD name
  export rook_toolspod=$(kubectl -n rook-ceph get pod -l app=rook-ceph-tools --no-headers -o custom-columns=:.metadata.name)
  kubectl -n rook-ceph exec -ti ${rook_toolspod} -- ceph dashboard set-login-credentials ${DEEPOPS_ROOK_USER} ${DEEPOPS_ROOK_PASS}
}


function get_opts() {
  while getopts "uhwdpx" option; do
    case $option in
      w)
        ROOK_CEPH_POLL=true
        ;;
      d)
        ROOK_DELETE=true
        ;;
      p)
        ROOK_PRINT=true
        ;;
      u)
        ROOK_CEPH_USER=true
        ;;
      x)
        DEEPOPS_ROOK_NO_DEFAULT="true"
        ;;
      h)
        help_me
        exit 1
        ;;
      * )
        help_me
        exit 1
        ;;
    esac
  done
}


function install_rook() {
  # Install Helm if it is not already installed
  ${SCRIPT_DIR}/install_helm.sh

  if ! kubectl get ns rook-ceph >/dev/null 2>&1 ; then
    kubectl create ns rook-ceph
  fi

  # https://github.com/rook/rook/blob/master/Documentation/helm-operator.md
  helm repo add rook-release "${HELM_ROOK_CHART_REPO}"

  # We need to dynamically set up Helm args, so let's use an array
  helm_install_args=("--namespace" "rook-ceph"
                     "--version" "${HELM_ROOK_CHART_VERSION}"
  )

  # Use an alternate image if set
  if [ "${ROOK_CEPH_IMAGE_REPO}" ]; then
    helm_install_args+=("--set" "image.repository=${ROOK_CEPH_IMAGE_REPO}")
  fi

  # Install rook-ceph
  if ! helm status -n rook-ceph rook-ceph >/dev/null 2>&1 ; then
    helm install rook-ceph rook-release/rook-ceph "${helm_install_args[@]}"
  fi

  if kubectl -n rook-ceph get pod -l app=rook-ceph-tools 2>&1 | grep "No resources found." >/dev/null 2>&1; then
    sleep 5
    # If we have an alternate registry defined, dynamically substitute it in
    if [ "${DEEPOPS_ROOK_DOCKER_REGISTRY}" ]; then
      sed "s/image: /image: ${DEEPOPS_ROOK_DOCKER_REGISTRY}\//g" workloads/services/k8s/rook-cluster.yml | kubectl create -f -
    else
      kubectl create -f workloads/services/k8s/rook-cluster.yml
    fi
  fi

  sleep 5

  if [ "${DEEPOPS_ROOK_NO_DEFAULT}" ]; then
    kubectl patch StorageClass ${DEEPOPS_ROOK_SC_NAME} -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
  fi

  print_rook
}


get_opts ${@}

if [ ${ROOK_DELETE} ]; then
  delete_rook
elif [ ${ROOK_CEPH_USER} ]; then
  create_ceph_user
elif [ ${ROOK_CEPH_POLL} ]; then
  poll_ceph
elif [ ${ROOK_PRINT} ]; then
  print_rook
else
  install_rook
fi
