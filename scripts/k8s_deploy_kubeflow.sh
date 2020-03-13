#!/usr/bin/env bash

# Get the DeepOps root_dir and config_dir
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."
CONFIG_DIR="${ROOT_DIR}/config"

# Specify credentials for the default user.
# TODO: Dynamically sed/hash these value into the CONFIG, these are currently not used
export KUBEFLOW_USER_EMAIL="${KUBEFLOW_USER_EMAIL:-admin@kubeflow.org}"
export KUBEFLOW_PASSWORD="${KUBEFLOW_PASSWORD:-12341234}"

# Speificy how long to poll for Kubeflow to start
export KUBEFLOW_TIMEOUT="${KUBEFLOW_TIMEOUT:-600}"

# Local files/directories to create and place scripts
export KF_DIR="${KF_DIR:-${CONFIG_DIR}/kubeflow-install}"
export KFCTL="${KFCTL:-${CONFIG_DIR}/kfctl}"
export KUBEFLOW_DEL_SCRIPT="${KF_DIR}/deepops-delete-kubeflow.sh"

# Download URLs and versions
export KFCTL_FILE=kfctl_v1.0-rc.1-0-g963c787_linux.tar.gz
export KFCTL_URL="https://github.com/kubeflow/kfctl/releases/download/v1.0-rc.1/${KFCTL_FILE}"

# Config 1: https://www.kubeflow.org/docs/started/k8s/kfctl-existing-arrikto/
export CONFIG_URI="https://raw.githubusercontent.com/kubeflow/manifests/b37bad9eded2c47c54ce1150eb9e6edbfb47ceda/kfdef/kfctl_existing_arrikto.0.7.1.yaml"
export CONFIG_FILE="${KF_DIR}/kfctl_existing_arrikto.0.7.1.yaml"

# Config 2: https://www.kubeflow.org/docs/started/k8s/kfctl-k8s-istio/
export NO_AUTH_CONFIG_URI="https://raw.githubusercontent.com/kubeflow/manifests/v0.7-branch/kfdef/kfctl_k8s_istio.0.7.0.yaml"
export NO_AUTH_CONFIG_FILE="${KF_DIR}/kfctl_k8s_istio.0.7.0.yaml"


function help_me() {
  echo "Usage:"
  echo "-h    This message."
  echo "-p    Print out the connection info for Kubeflow"
  echo "-d    Delete Kubeflow from your system (skipping the CRDs and istio-system namespace that may have been installed with Kubeflow"
  echo "-D    Full Delete Kubeflow from your system along with all Kubeflow CRDs the istio-system namespace. WARNING, do not use this option if other components depend on istio."
  echo "-x    Install Kubeflow without multi-user auth (this option is deprecated)"
  echo "-c    Specify a different Kubeflow config to install with"
  echo "-w    Wait for Kubeflow homepage to respond"
}


function get_opts() {
  while getopts "hpwc:xdD" option; do
    case $option in
      p)
        KUBEFLOW_PRINT=true
        ;;
      c)
	CONFIG=$OPTARG
        ;;
      w)
        KUBEFLOW_WAIT=true
        ;;
      x)
	CONFIG_URI=${NO_AUTH_CONFIG_URI}
	CONFIG_FILE=${NO_AUTH_CONFIG_FILE}
	SKIP_LB=true
        ;;
      d)
        KUBEFLOW_DELETE=true
        ;;
      D)
        KUBEFLOW_DELETE=true
        KUBEFLOW_FULL_DELETE=true
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
  # TODO: This kfctl delete seems to be failing due to a Kubeflow config bug
  echo "cd ${KF_DIR} && ${KFCTL} delete -V -f ${CONFIG_FILE} --delete_storage; cd && sudo rm -rf ${KF_DIR}" > ${KUBEFLOW_DEL_SCRIPT}
  chmod +x ${KUBEFLOW_DEL_SCRIPT}

  # Initialize and apply the Kubeflow project using the specified config. We do this in two steps to allow a chance to customize the config
  cd ${KF_DIR}
  ${KFCTL} build -V -f ${CONFIG_URI}

  # Update Kubeflow with the NGC containers and NVIDIA configurations
  ${SCRIPT_DIR}/update_kubeflow_config.py

  # XXX: Add potential CONFIG customizations here before applying
  ${KFCTL} apply -V -f ${CONFIG_FILE}
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

  # Delete other NS that were installed. These might be part of other apps and is slightly dangerous
  if [ "${KUBEFLOW_FULL_DELETE}" == "true" ]; then
    namespaces=" ${namespaces} admin auth cert-manager istio-system knative-serving ${KUBEFLOW_EXTRA_NS}"
  fi

  # This runs kfctl delete pointing to the CONFIG that was used at install
  bash ${KUBEFLOW_DEL_SCRIPT} && sleep 5 # There seems to be a timing issue here in kfctl, so we sleep a bit.

  # delete all namespaces, including namespaces that "should" already have been deleted by kfctl delete
  echo "Re-deleting namespaces ${namespaces} for a full cleanup"
  kubectl delete ns ${namespaces}

  # There is an issues in the kfctl delete command that does not properly clean up and leaves NSs in a terminating state, this is a bit hacky but resolves it
  # echo "Removing finalizers from all namespaces: ${namespaces}"
  # fix_terminating_ns ${namespaces}

  if [ "${KUBEFLOW_FULL_DELETE}" == "true" ]; then
    # These should probably be deleted by kfctl, but they are not
    kubectl delete crd -l app.kubernetes.io/part-of=kubeflow -o name
    kubectl delete all -l app.kubernetes.io/part-of=kubeflow --all-namespaces
  fi

  rm ${KFCTL}
}


function poll_url() {
  # It typically takes ~5 minutes for all pods and services to start, so we poll for ten minutes here
  time=0
  while [ ${time} -lt ${KUBEFLOW_TIMEOUT} ]; do
    # XXX: This validates that the webapp is responding, it does not guarentee functionality
    curl -s --raw -L "${kf_url}" && \
      echo "Kubeflow homepage is up" && exit 0
    let time=$time+15
    sleep 15
  done
  echo "Kubeflow did not respond within ${KUBEFLOW_TIMEOUT} seconds"
  exit 1
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
  # echo "Kubeflow Dashboard (HTTPS NodePort, required for auth): ${secure_kf_url}"
  # echo "Kubeflow Dashboard (DEFAULT - LoadBalancer, required for auth w/Dex): ${lb_url}"
  echo
}


function test_script() {
  # Don't test recursively
  if [ ${KUBEFLOW_TEST} ]; then
    export KUBEFLOW_TEST=""
  else
    return
  fi

  ./${0} -dp
  if [ ${?} -eq 0 ]; then
    exit 10
  fi
  ./${0} -h
  if [ ${?} -eq 0 ]; then
    exit 11
  fi
  
  ./${0}
  if [ ${?} -ne 0 ]; then
    exit 12 # we should really test with a curl
  fi
  ./${0} -D
  if [ ${?} -ne 0 ]; then
    exit 13
  fi
  ./${0} -x
  if [ ${?} -ne 0 ]; then
    exit 14
  fi
  ./${0} -e
  if [ ${?} -ne 0 ]; then
    exit 15
  fi

  exit 0
}

test_script

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
  get_url
  print_info
fi
