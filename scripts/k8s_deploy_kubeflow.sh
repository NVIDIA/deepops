#!/usr/bin/env bash

# Get the DeepOps root_dir and config_dir
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."
CONFIG_DIR="${ROOT_DIR}/config"

# Specify credentials for the default user.
# TODO: Dynamically sed/hash these value into the CONFIG, these are currently not used
export KUBEFLOW_USER_EMAIL="${KUBEFLOW_USER_EMAIL:-admin@kubeflow.org}"
export KUBEFLOW_PASSWORD="${KUBEFLOW_PASSWORD:-12341234}"

# Poll for these to be available with the -w flag
KUBEFLOW_POLL_DEPLOYMENTS="${KUBEFLOW_DEPLOYMENTS:-profiles-deployment notebook-controller-deployment centraldashboard ml-pipeline minio mysql metadata-db jupyter-web-app-deployment katib-mysql}"

# Speificy how long to poll for Kubeflow to start
export KUBEFLOW_TIMEOUT="${KUBEFLOW_TIMEOUT:-600}"

# Local files/directories to create and place scripts
export KF_DIR="${KF_DIR:-${CONFIG_DIR}/kubeflow-install}"
export KFCTL="${KFCTL:-${CONFIG_DIR}/kfctl}"
export KUSTOMIZE="${KUSTOMIZE:-${CONFIG_DIR}/kustomize}"
export KUBEFLOW_DEL_SCRIPT="${KF_DIR}/deepops-delete-kubeflow.sh"

export KUBEFLOW_MPI_DIR="${KUBEFLOW_MPI_DIR:-${KF_DIR}/mpi}"
export KUBEFLOW_MPI_MANIFESTS_REPO="${KUBEFLOW_MPI_MANIFESTS_REPO:-https://github.com/kubeflow/manifests}"

# Download URLs and versions, note the kfctl version does not always match the manifest/config version, but best-effort should be made to keep their versions close
export KFCTL_FILE=kfctl_v1.1.0-0-g9a3621e_linux.tar.gz # https://github.com/kubeflow/kfctl/releases/tag/v1.1.0
export KFCTL_URL="https://github.com/kubeflow/kfctl/releases/download/v1.1.0/${KFCTL_FILE}"
export AUTH_KFCTL_FILE=kfctl_v1.1.0-0-g9a3621e_linux.tar.gz # https://github.com/kubeflow/kfctl/releases/tag/v1.1.0
export AUTH_KFCTL_URL="https://github.com/kubeflow/kfctl/releases/download/v1.1.0/${KFCTL_FILE}"

# Config 1: https://www.kubeflow.org/docs/started/k8s/kfctl-existing-arrikto/
export AUTH_CONFIG_URI="https://raw.githubusercontent.com/kubeflow/manifests/6dcebbe263bc98c62aee9bff4364f7dfb3efe254/kfdef/kfctl_istio_dex.v1.1.0.yaml"
export AUTH_CONFIG_FILE="${KF_DIR}/kfctl_istio_dex.v1.1.0.yaml" # Not yet a release version, but likely https://github.com/kubeflow/manifests/releases/tag/v1.1-rc.3

# Config 2: https://www.kubeflow.org/docs/started/k8s/kfctl-k8s-istio/
export CONFIG_URI="https://raw.githubusercontent.com/kubeflow/manifests/master/kfdef/kfctl_k8s_istio.yaml" # Not a hash or branch tag because of https://github.com/kubeflow/manifests/pull/1459
export CONFIG_FILE="${KF_DIR}/kfctl_k8s_istio.yaml" #  Not v1.0.2 due to https://github.com/kubeflow/manifests/issues/991



function help_me() {
  echo "Usage:"
  echo "-h    This message."
  echo "-p    Print out the connection info for Kubeflow."
  echo "-d    Delete Kubeflow from your system (skipping the CRDs and istio-system namespace that may have been installed with Kubeflow."
  echo "-D    Deprecated, same as -d. Previously 'Fully Delete Kubeflow from your system along with all Kubeflow CRDs the istio-system namespace. WARNING, do not use this option if other components depend on istio.'"
  echo "-x    Install Kubeflow with multi-user auth (this utilizes Dex, the default is no multi-user auth)."
  echo "-w    Wait for Kubeflow homepage to respond (also polls for various Kubeflow Deployments to have an available status)."
}


function get_opts() {
  while getopts "hpwxdDZ" option; do
    case $option in
      p)
        KUBEFLOW_PRINT=true
        ;;
      w)
        KUBEFLOW_WAIT=true
        ;;
      x)
	CONFIG_URI=${AUTH_CONFIG_URI}
	CONFIG_FILE=${AUTH_CONFIG_FILE}
        KFCTL_FILE="${AUTH_KFCTL_FILE}"
        KFCTL_URL="${AUTH_KFCTL_URL}"
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

  # Rook
  kubectl get storageclass 2>&1 | grep "No resources found." >/dev/null 2>&1
  if [ $? -eq 0 ] ; then
      echo "No storageclass found"
      echo "To provision Ceph storage, run: ./scripts/k8s_deploy_rook.sh"
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


function install_mpi_operator() {

  # Download kustomize, as required by mpi
  pushd .
  cd ${CONFIG_DIR}
  curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases |\
    grep browser_download |\
    grep linux |\
    cut -d '"' -f 4 |\
    grep /kustomize/v |\
    sort | tail -n 1 |\
    xargs curl -s -O -L
  tar xzf ./kustomize_v*_linux_amd64.tar.gz
  mv kustomize ${KUSTOMIZE}

  mkdir -p ${KUBEFLOW_MPI_DIR}
  cd ${KUBEFLOW_MPI_DIR}
  git clone ${KUBEFLOW_MPI_MANIFESTS_REPO}
  cd manifests/mpi-job/mpi-operator
  ${KUSTOMIZE} build base | kubectl apply -f -

  popd # Go back to the original dir
}


function stand_up() {
  # Download the kfctl binary and move it to the default location
  pushd .
  mkdir ${CONFIG_DIR}/tmp-kf-download
  cd ${CONFIG_DIR}/tmp-kf-download
  curl -O -L ${KFCTL_URL}
  tar -xvf ${KFCTL_FILE}
  mv kfctl ${KFCTL}
  popd
  rm -rf ${CONFIG_DIR}/tmp-kf-download

  # Create directory for KF files
  mkdir ${KF_DIR}

  # Make cleanup scripts first in case deployment fails
  # TODO: This kfctl delete seems to be failing occasionally with the cert-manager ns (due to a Kubeflow config bug)
  # XXX: We manually delete the mpijobs crd because this is currently installed outside of the kfctl apply
  echo "kubectl delete crd mpijobs.kubeflow.org; cd ${KF_DIR} && ${KFCTL} delete -V -f ${CONFIG_FILE} --force-deletion --delete_storage; cd && sudo rm -rf ${KF_DIR}" > ${KUBEFLOW_DEL_SCRIPT}
  chmod +x ${KUBEFLOW_DEL_SCRIPT}

  # Initialize and apply the Kubeflow project using the specified config. We do this in two steps to allow a chance to customize the config
  pushd .
  cd ${KF_DIR}
  ${KFCTL} build -V -f ${CONFIG_URI}

  # Occassionally the kfctl will fail, if this occurs halt all installation
  if [ $? != 0 ]; then
    echo -e "\nDeepOps ERROR: Failure building Kubeflow Manifest at ${CONFIG_URI} in ${KF_DIR}"
     exit 1
  fi

  sed -i '/metadata:.*/a\  ClusterName: cluster.local' ${CONFIG_FILE} # BUGFIX: Need to add the ClusterName for proper deletion:https://github.com/kubeflow/kubeflow/issues/4815

  # Update Kubeflow with the NGC containers and NVIDIA configurations
  # BUG: Commented out until NGC containers add Kubeflow support, see https://github.com/NVIDIA/deepops/tree/master/containers/ngc
  # ${SCRIPT_DIR}/update_kubeflow_config.py

  # XXX: Add potential CONFIG customizations here before applying
  ${KFCTL} apply -V -f ${CONFIG_FILE}
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
  # Kubeflow use leads to some user created namespaces that are not torn down during kfctl delete
  namespaces="kubeflow"

  # This runs kfctl delete pointing to the CONFIG that was used at install
  bash ${KUBEFLOW_DEL_SCRIPT}

  # There is an issues in the kfctl delete command that does not properly clean up and leaves NSs in a terminating state, this is a bit hacky but resolves it
  if [ "${KUBEFLOW_EXTRA_FULL_DELETE}" == "true" ]; then
    echo "Removing finalizers from all namespaces: ${namespaces}"
    fix_terminating_ns ${namespaces}
  fi

  rm ${KFCTL}
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
else
  install_dependencies
  stand_up
  install_mpi_operator
  get_url
  print_info
fi
