#!/usr/bin/env bash

# Get the DeepOps root_dir and config_dir
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."
CONFIG_DIR="${ROOT_DIR}/config"

# Source common libraries and env variables
source ${ROOT_DIR}/scripts/common.sh

# Poll for these to be available with the -w flag
KUBEFLOW_POLL_DEPLOYMENTS="${KUBEFLOW_DEPLOYMENTS:-profiles-deployment notebook-controller-deployment centraldashboard ml-pipeline minio mysql jupyter-web-app-deployment katib-mysql}"

# Specify how long to poll for Kubeflow to start
export KUBEFLOW_TIMEOUT="${KUBEFLOW_TIMEOUT:-600}"
export KUBEFLOW_DEPLOY_TIMEOUT="${KUBEFLOW_DEPLOY_TIMEOUT:-1200}"

# Define Kubeflow manifests location
export KUBEFLOW_MANIFESTS_DEST="${KUBEFLOW_MANIFESTS_DEST:-${CONFIG_DIR}/kubeflow-install/manifests}"
export KUBEFLOW_MANIFESTS_URL="${KUBEFLOW_MANIFESTS_URL:-https://github.com/kubeflow/manifests}"
export KUBEFLOW_MANIFESTS_VERSION="${KUBEFLOW_MANIFESTS_VERSION:-v1.4.1}"

# Define configuration we're injecting into the manifests location
export KUBEFLOW_DEEPOPS_CONFIG_DIR="${KUBEFLOW_DEEPOPS_CONFIG_DIR:-${CONFIG_DIR}/files/kubeflow}"
export KUBEFLOW_DEEPOPS_DEX_CONFIG="${KUBEFLOW_DEEPOPS_DEX_CONFIG:-${KUBEFLOW_DEEPOPS_CONFIG_DIR}/dex-config-map.yaml}"
export KUBEFLOW_DEEPOPS_USERNS_PARAMS="${KUBEFLOW_DEEPOPS_USERNS_PARAMS:-${KUBEFLOW_DEEPOPS_CONFIG_DIR}/user-namespace-params.env}"

# Define Kustomize location
export KUSTOMIZE_URL="${KUSTOMIZE_URL:-https://github.com/kubernetes-sigs/kustomize/releases/download/v3.2.0/kustomize_3.2.0_linux_amd64}"
export KUSTOMIZE="${KUSTOMIZE:-${CONFIG_DIR}/kustomize}"

function help_me() {
  echo "Usage:"
  echo "-h    This message."
  echo "-p    Print out the connection info for Kubeflow."
  echo "-c    Only clone the Kubeflow manifests repo, but do not deploy Kubeflow."
  echo "-d    Delete Kubeflow from your system (skipping the CRDs and istio-system namespace that may have been installed with Kubeflow."
  echo "-D    Deprecated, same as -d. Previously 'Fully Delete Kubeflow from your system along with all Kubeflow CRDs the istio-system namespace. WARNING, do not use this option if other components depend on istio.'"
  echo "-x    Deprecated, multi-user auth is now the default." 
  echo "-w    Wait for Kubeflow homepage to respond (also polls for various Kubeflow Deployments to have an available status)."
}


function get_opts() {
  while getopts "chpwxdDZ" option; do
    case $option in
      p)
        KUBEFLOW_PRINT=true
        ;;
      w)
        KUBEFLOW_WAIT=true
        ;;
      c)
	KUBEFLOW_CLONE=true
	;;
      x)
        ;;
      d)
        KUBEFLOW_DELETE=true
        ;;
      D)
        KUBEFLOW_DELETE=true
        echo "The -D flag is deprecated, use -d instead"
        ;;
      Z)
	# This is a dangerous command and is not included in the help
	KUBEFLOW_EXTRA_FULL_DELETE=true
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


function install_dependencies() {
  # Install dependencies
  . /etc/os-release
  case "$ID" in
      rhel*|centos*)
          type curl >/dev/null 2>&1
          if [ $? -ne 0 ] ; then
              sudo yum -y install curl wget
          fi
          ;;
      ubuntu*)
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

  # StorageClass (for volumes and MySQL DB)
  kubectl get storageclass 2>&1 | grep "(default)" >/dev/null 2>&1
  if [ $? -ne 0 ] ; then
      echo "No storageclass found"
      echo "To setup the nfs-client-provisioner (preferred), run: ansible-playbook playbooks/k8s-cluster/nfs-client-provisioner.yml"
      echo "To provision Ceph storage, run: ./scripts/k8s/deploy_rook.sh"
      exit 1
  fi
  
  # Proxies
  if [ ${http_proxy} -o ${https_proxy} -o ${no_proxy} ]; then
      echo "Proxy detected. This could cause problems with a default Kubeflow installation."
      echo "Refer to the workaround here: https://github.com/kubeflow/kfctl/issues/237"
      echo "After applying the workaround run: KUBEFLOW_PROXY_WORKAROUND=true ./${0}"
      if [ -z ${KUBEFLOW_PROXY_WORKAROUND} ]; then
          exit 1
      fi
  fi
}

function clone_repo() {
  pushd .
  if [ -d "${KUBEFLOW_MANIFESTS_DEST}" ]; then
    echo "Kubeflow manifests directory already exists at: ${KUBEFLOW_MANIFESTS_DEST}"
    echo "Exiting script! Please delete this directory before re-deploying."
    exit 1
  fi
  mkdir -p "${KUBEFLOW_MANIFESTS_DEST}"
  pushd "${KUBEFLOW_MANIFESTS_DEST}"
  git clone -b "${KUBEFLOW_MANIFESTS_VERSION}" "${KUBEFLOW_MANIFESTS_URL}" .

  # Inject custom dex config
  cp -v "${KUBEFLOW_DEEPOPS_DEX_CONFIG}" "${KUBEFLOW_MANIFESTS_DEST}/common/dex/base/config-map.yaml"
  cp -v "${KUBEFLOW_DEEPOPS_USERNS_PARAMS}" "${KUBEFLOW_MANIFESTS_DEST}/common/user-namespace/base/params.env"

  popd
  echo "Kubeflow manifests repo:"
  echo "- Cloned from: ${KUBEFLOW_MANIFESTS_URL}"
  echo "- Git branch or tag: ${KUBEFLOW_MANIFESTS_VERSION}"
  echo "- Local path: ${KUBEFLOW_MANIFESTS_DEST}"
}

function stand_up() {
  pushd .
  pushd "${KUBEFLOW_MANIFESTS_DEST}"

  wget -O "${KUSTOMIZE}" "${KUSTOMIZE_URL}"
  chmod +x "${KUSTOMIZE}"

  echo "Beginning Kubeflow deployment"
  timeout "${KUBEFLOW_DEPLOY_TIMEOUT}" bash -c -- "while ! ${KUSTOMIZE} build example | kubectl apply -f -; do sleep 10; done"
  if [ $? -eq 124 ]; then
    echo "Timed out attempt to deploy Kubeflow"
    popd
    exit 1
  fi
  popd
}


# Modify the ns finalizers so they don't wait for async processes to complete
function fix_terminating_ns() {
  kubectl proxy &
  for ns in ${@}; do
    kubectl get namespace ${ns} -o json |jq '.spec = {"finalizers":[]}' > "/tmp/temp_${ns}.json"
    curl -k -H "Content-Type: application/json" -X PUT --data-binary @"/tmp/temp_${ns}.json" 127.0.0.1:8001/api/v1/namespaces/${ns}/finalize
  done
}


function tear_down() {
  # TODO add a confirmation dialog
  # TODO allow limiting namespace list
  namespaces="kubeflow knative-eventing knative-serving"

  echo "Tearing down Kubeflow installation!"
  echo "Removing all objects in Kubernetes namespaces: ${namespaces}"
  echo
  echo "WARNING: This script does not delete the istio-system or cert-manager namespaces,"
  echo "because these are commonly used by other applications."
  echo
  echo "If you want to remove these namespaces, please do so manually by running:"
  echo "  kubectl delete namespace istio-system cert-manager"
  echo

  for ns in $(echo "${namespaces}"); do
    kubectl delete namespace "${ns}"
  done

  # There is an issues in the kfctl delete command that does not properly clean up and leaves NSs in a terminating state, this is a bit hacky but resolves it
  if [ "${KUBEFLOW_EXTRA_FULL_DELETE}" == "true" ]; then
    echo "Removing finalizers from all namespaces: ${namespaces}"
    fix_terminating_ns ${namespaces}
  fi
}


function poll_url() {
  kubectl wait --for=condition=available --timeout=${KUBEFLOW_TIMEOUT}s -n kubeflow deployments ${KUBEFLOW_POLL_DEPLOYMENTS}
  if [ "${?}" != "0" ]; then
    echo "Kubeflow did not complete deployment within ${KUBEFLOW_TIMEOUT} seconds"
    exit 1
  fi

  # It typically takes ~5 minutes for all pods and services to start, so we poll for ten minutes here
  time=0
  while [ ${time} -lt ${KUBEFLOW_TIMEOUT} ]; do
    # XXX: This validates that the webapp is responding, it does not guarentee functionality
    curl -s --raw -L "${kf_url}" && \
      echo "Kubeflow homepage is up" && break
    let time=$time+15
    sleep 15
  done
  curl -s --raw -L "${kf_url}" || (echo "Kubeflow did not respond within ${KUBEFLOW_TIMEOUT} seconds" && \
    exit 1) # Fail if we didn't come up in time.
}


function get_url() {
  # Get LoadBalancer and NodePorts
  master_ip=$(kubectl get nodes -l node-role.kubernetes.io/master= --no-headers -o custom-columns=IP:.status.addresses.*.address | cut -f1 -d, | head -1)
  nodePort="$(kubectl get svc -n istio-system istio-ingressgateway --no-headers -o custom-columns=PORT:.spec.ports[?\(@.name==\"http2\"\)].nodePort)"
  secure_nodePort="$(kubectl get svc -n istio-system istio-ingressgateway --no-headers -o custom-columns=PORT:.spec.ports[?\(@.name==\"https\"\)].nodePort)"
  lb_ip="$(kubectl get svc -n istio-system istio-ingressgateway --no-headers -o custom-columns=:.status.loadBalancer.ingress[0].ip)"
  export kf_url="http://${master_ip}:${nodePort}"
  export secure_kf_url="https://${master_ip}:${secure_nodePort}"
  export lb_url="https://${lb_ip}"
}


function print_info() {
  echo
  echo "Kubeflow app installed to: ${KF_DIR}"
  echo
  echo "It may take several minutes for all services to start. Run 'kubectl get pods -n kubeflow' to verify"
  echo
  echo "To remove (excluding CRDs, istio, auth, and cert-manager), run: ${0} -d"
  echo
  echo "To perform a full uninstall : ${0} -D"
  echo
  echo "Kubeflow Dashboard (HTTP NodePort): ${kf_url}"
  echo
}


get_opts ${@}

if [ ${KUBEFLOW_PRINT} ] && [ ${KUBEFLOW_DELETE} ]; then
  echo "Cannot specify print flag and delete flag"
  exit 2
elif [ ${KUBEFLOW_PRINT} ]; then
  get_url
  print_info
elif [ ${KUBEFLOW_DELETE} ]; then
  tear_down
elif [ ${KUBEFLOW_WAIT} ]; then
  # Run print_info to get the kf_url
  get_url
  print_info
  poll_url
elif [ ${KUBEFLOW_CLONE} ]; then
  clone_repo
else
  install_dependencies
  clone_repo
  stand_up
  # install_mpi_operator # BUG: https://github.com/NVIDIA/deepops/issues/737
  get_url
  print_info
fi
