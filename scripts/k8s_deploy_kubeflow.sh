#!/usr/bin/env bash

# Local files/directories to create and place scripts
export KF_DIR=${KF_DIR:-~/kubeflow}
export KFCTL=${KFCTL:-~/kfctl}
export KUBEFLOW_DEL_SCRIPT="${KF_DIR}/deepops-delete-kubeflow.sh"

# Download URLs and versions
export KUBEFLOW_TAG=v0.7.0
export KFCTL_URL=https://github.com/kubeflow/kubeflow/releases/download/${KUBEFLOW_TAG}/kfctl_${KUBEFLOW_TAG}_linux.tar.gz

# Config 1: https://www.kubeflow.org/docs/other-guides/kustomize/
export CONFIG_URI="https://raw.githubusercontent.com/kubeflow/manifests/v0.7-branch/kfdef/kfctl_existing_arrikto.0.7.0.yaml"
export CONFIG_FILE="${KF_DIR}/kfctl_existing_arrikto.0.7.0.yaml"

# Config 2: https://www.kubeflow.org/docs/started/k8s/kfctl-existing-arrikto/
export NO_AUTH_CONFIG_URI="https://raw.githubusercontent.com/kubeflow/manifests/v0.7-branch/kfdef/kfctl_k8s_istio.0.7.0.yaml"
export NO_AUTH_CONFIG_FILE="${KF_DIR}/kfctl_k8s_istio.0.7.0.yaml"


# Specify credentials for the default user.
export KUBEFLOW_USER_EMAIL="${KUBEFLOW_USER_EMAIL:-admin@kubeflow.org}"
export KUBEFLOW_PASSWORD="${KUBEFLOW_PASSWORD:-12341234}"


function help_me() {
  echo "Usage:"
  echo "-h    This message."
  echo "-p    Print out the connection info for Kubeflow"
  echo "-d    Delete Kubeflow from your system (skipping the istio-system namespace that may have been installed with Kubeflow"
  echo "-D    Delete Kubeflow from your system along with the istio-system namespace. WARNING, do not use this option if other components depend on istio."
  echo "-x    Install Kubeflow without multi-user auth (this does not require loadbalancing"
  echo "-c    Specify a different Kubeflow config to install with"
}


function get_opts() {
  while getopts "hpc:xdD" option; do
    case $option in
      p)
        KUBEFLOW_PRINT=true
        ;;
      c)
	CONFIG=$OPTARG
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
}


function stand_up() {
  # Download the kfctl binary and move it to the default location
  pushd .
  mkdir /tmp/kf-download
  cd /tmp/kf-download
  curl -O -L ${KFCTL_URL}
  tar -xvf kfctl_${KUBEFLOW_TAG}_linux.tar.gz
  mv kfctl ${KFCTL}
  popd
  rm -rf /tmp/kf-download

  # Create directory for KF files
  mkdir ${KF_DIR}

  # Make cleanup scripts first in case deployment fails
  echo "cd ${KF_DIR} && ${KFCTL} delete -V -f ${CONFIG_FILE} --delete_storage; cd && sudo rm -rf ${KF_DIR}" > ${KUBEFLOW_DEL_SCRIPT}
  chmod +x ${KUBEFLOW_DEL_SCRIPT}

  # Initialize and apply the Kubeflow project using the specified config. We do this in two steps to allow a chance to customize the config
  cd ${KF_DIR}
  ${KFCTL} build -V -f ${CONFIG_URI}
  # TODO: Add potential CONFIG customizations here in CONFIG_FILE
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
    namespaces=" ${namespaces} kubeflow-anonymous auth anonymous cert-manager istio-system knative-serving ${KUBEFLOW_EXTRA_NS}"
  fi

  # This runs kfctl delete pointing to the CONFIG that was used at install
  bash ${KUBEFLOW_DEL_SCRIPT} && sleep 5 # There seems to be a timing issue here in kfctl, so we sleep a bit.

  # delete all namespaces, including namespaces that "should" already have been deleted by kfctl delete
  echo "Re-deleting namespaces ${namespaces} for a full cleanup"
  kubectl delete ns ${namespaces}

  # There is an issues in the kfctl delete command that does not properly clean up and leaves NSs in a terminating state, this is a bit hacky but resolves it
  echo "Removing finalizers from all namespaces: ${namespaces}"
  fix_terminating_ns ${namespaces}

  rm ${KFCTL}
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
  echo "To remove (excluding istio, auth, and cert-manager), run: ${0} -d"
  echo "To remove all installed components and the kfctl binary: ${0} -D"
  echo "Alternatively, to manually uninstall everything run:"
  echo "bash ${KUBEFLOW_DEL_SCRIPT}"
  echo 
  echo "Kubeflow Dashboard (HTTP NodePort): ${kf_url}"
  echo "Kubeflow Dashboard (HTTPS NodePort, required for auth): ${secure_kf_url}"
  echo "Kubeflow Dashboard (DEFAULT - LoadBalancer, required for auth w/Dex): ${lb_url}"
  echo
  echo "It may take several minutes for all services to start. Run 'kubectl get pods -n kubeflow' to verify"
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
else
  install_dependencies
  stand_up
  get_url
  print_info
fi
