#!/bin/bash -ex

# In order for this deployment to properly work across your cluster you will need to build the customer Docker image and push it out to your local Docker repository

# This script will create a dask cluster including 1 Jupyter container,  1 Dask  scheduler, and N Dask workers.
# The Dask workers can be scaled from  the K8S command line using `kubectl scale` commands or through jupyter using dask_kubernetes commands
# See the included sample notebooks for details.

# Global K8S/Helm variables
RAPIDS_DASK_DOCKER_REPO="${RAPIDS_DASK_DOCKER_REPO:-https://github.com/supertetelman/k8s-rapids-dask.git}"
RAPIDS_DASK_DOCKER_REPO_BRANCH=${RAPIDS_DASK_DOCKER_REPO_BRANCH:-master}
DASK_CHART_NAME=stable/dask
DOCKER_REGISTRY=registry.local
app_name="dask" # App name from helm chart

# Variables based on helm charts
pod_count_scale=3 # number of expected pods after scale down to 1 worker
pod_count_scale_down=2 # number of expected pods after scale down to 0 workers
pod_count=3 # number of expected pods after initialization


function help_me() {
  echo "Usage:"
  echo "-h    This message."
  echo "-n    Kubernetes namespace"
  echo "-d    Docker image name"
  echo "-p    Push the Docker image after building it"
  echo "-b    Build the Docker image, default is to pull from DockerHub"
  echo "-c    The number of Pods already running in this namespace (if deploying to existing namespace)"
}


function get_opts() {
while getopts "bc:n:d:pth" option; do
  case $option in
    n)
      RAPIDS_NAMESPACE=$OPTARG
      ;;
    d)
      DASK_IMAGE=$OPTARG
      ;;
    b)
      BUILD_IMAGE=true
      ;;
    p)
      PUSH_IMAGE=true
      ;;
    c)
      count=$OPTARG
      let pod_count=${pod_count}+${count}
      let pod_count_scale_down=${pod_count_scale_down}+${count}
      let pod_count_scale=${pod_count_scale}+${count}
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

# Set default values if they were not specified
RAPIDS_NAMESPACE="${RAPIDS_NAMESPACE:-rapids}"
RAPIDS_HELM_NAME=${RAPIDS_HELM_NAME:-${RAPIDS_NAMESPACE}-rapids}
RAPIDS_TMP_BUILD_DIR="${RAPIDS_TMP_BUILD_DIR:-tmp-rapids-build}"
DASK_IMAGE="${DASK_IMAGE:-dask-rapids}"
}


function build_image() {
  if [ -z ${BUILD_IMAGE} ]; then
    return
  fi

  echo "Building custom dask/rapids image: ${DASK_IMAGE}"

  if [ -d "${RAPIDS_TMP_BUILD_DIR}" ]; then
	  read -r -p "rapids build directory (${RAPIDS_TMP_BUILD_DIR}) already exist, would you  like to delete it? (yes/no)" response
    case "$response" in
      [yY][eE][sS]|[yY])
	rm -rf "${RAPIDS_TMP_BUILD_DIR}"
	;;
      *)
        echo "Quitting install"
	exit
	;;
    esac
  fi	  
  git clone --depth=1 --single-branch --branch ${RAPIDS_DASK_DOCKER_REPO_BRANCH} "${RAPIDS_DASK_DOCKER_REPO}" "${RAPIDS_TMP_BUILD_DIR}"
  pushd "${RAPIDS_TMP_BUILD_DIR}"

  # Build the docker image
  docker build --network=host -t ${DASK_IMAGE} .

  popd
  rm -rf "${RAPIDS_TMP_BUILD_DIR}"
  if [ "${DOCKER_PUSH}" != "" ]; then
    docker tag ${DASK_IMAGE} ${DOCKER_REGISTRY}/${DASK_IMAGE}
    docker push ${DOCKER_REGISTRY}/${DASK_IMAGE}
  fi
}


function tear_down() {
  # Delete existing resources
  if [ "$(helm list ${RAPIDS_HELM_NAME})" != "" ]; then
    read -r -p "Helm resources already exist, would you  like to delete them (this will include associated non-helm k8s service accounts as well)? (yes/no/skip)" response
    case "$response" in
      [yY][eE][sS]|[yY])
        helm uninstall --namespace ${RAPIDS_NAMESPACE} ${RAPIDS_HELM_NAME}
        kubectl delete -n ${RAPIDS_NAMESPACE} -f config/k8s/rapids-dask-sa.yml || true # Best effort to delete any existing service accounts in the ns
        sleep 2
        ;;
      skip)
        echo "Continuing with no cleanup"
        ;;
      *)
        echo "Quitting install"
        exit
        ;;
    esac
  fi

  if [ "$(kubectl get ns ${RAPIDS_NAMESPACE})" != "" -a "${RAPIDS_SKIP_KUBERNETES}" != "true"  ]; then
    read -r -p "Kubernetes resources already exist, would you  like to delete them? (yes/no/skip)" response
    case "$response" in
      [yY][eE][sS]|[yY])
        kubectl delete ns ${RAPIDS_NAMESPACE}
        sleep 2
        ;;
      skip)
        echo "Continuing with no cleanup"
        ;;
      *)
        echo "Quitting install"
        exit
        ;;
    esac
  fi
}


function stand_up() {
  echo "installing dask via helm"

  # Create the Dask resources
  kubectl create ns ${RAPIDS_NAMESPACE}
  helm install ${RAPIDS_HELM_NAME} ${DASK_CHART_NAME} --namespace ${RAPIDS_NAMESPACE} --values config/helm/rapids-dask.yml
  kubectl create -n ${RAPIDS_NAMESPACE} -f config/k8s/rapids-dask-sa.yml

  # kubectl create -f  config/k8s/rapids-dask-autoscale.yml # XXX: Optional install
  kubectl wait -n ${RAPIDS_NAMESPACE} --for=condition=Ready -l "app=${app_name}" --timeout=90s pod 
}


function copy_config() {
  echo "Copying dask-worker yaml file into running jupyter container"
  kubectl -n ${RAPIDS_NAMESPACE} scale deployment ${RAPIDS_HELM_NAME}-dask-worker --replicas=1
  # Wait for containers to initialize
  kubectl wait -n ${RAPIDS_NAMESPACE} --for=condition=Ready -l "app=${app_name}" --timeout=90s pod 

  # Copy worker spec over to Jupyter for Manual cluster  definition
  ## Get the names of the running pods
  worker_name=$(kubectl -n ${RAPIDS_NAMESPACE} get pods --no-headers=true -o custom-columns=:metadata.name | grep worker | tail -n1)
  jupyter_name=$(kubectl -n ${RAPIDS_NAMESPACE} get pods --no-headers=true -o custom-columns=:metadata.name | grep jupyter | tail -n1)
  spec="config/worker-spec-dynamic.yaml"

  ## Copy the yaml files into the pods after parsing some invalid information out
  kubectl -n ${RAPIDS_NAMESPACE} get pods --export -o yaml ${worker_name} > ${spec}.tmp
  cat ${spec}.tmp | grep -v creationTimestamp | awk -F'status:' '{print $1}' > ${spec}
  kubectl -n ${RAPIDS_NAMESPACE} cp ${spec} ${jupyter_name}:/rapids/notebooks

  # Scale worker Deployment to 0 so it can be controlled via Jupyter rather than k8s directly
  # XXX: This is an issue until we figure  out how to  join the existing cluster/deployment with the dask_kubernetes flow
  kubectl -n ${RAPIDS_NAMESPACE} scale deployment ${RAPIDS_HELM_NAME}-dask-worker --replicas=0
  # Wait for containers to initialize
  kubectl wait -n ${RAPIDS_NAMESPACE} --for=condition=Ready -l "app=${app_name}" --timeout=90s pod 
}

function get_url() {
  # Output connection info
  jupyter_ip="$(kubectl -n ${RAPIDS_NAMESPACE} get svc ${RAPIDS_HELM_NAME}-dask-jupyter -ocustom-columns=:.status.loadBalancer.ingress[0].ip | tail -n1)"
  jupyter_port="$(kubectl -n ${RAPIDS_NAMESPACE} get svc ${RAPIDS_HELM_NAME}-dask-jupyter -ocustom-columns=:.spec.ports[0].nodePort | tail -n1)"
  dask_port="$(kubectl -n ${RAPIDS_NAMESPACE} get svc ${RAPIDS_HELM_NAME}-dask-scheduler -ocustom-columns=:.spec.ports[1].nodePort | tail -n1)"
  dask_ip="$(kubectl -n ${RAPIDS_NAMESPACE} get svc ${RAPIDS_HELM_NAME}-dask-scheduler -ocustom-columns=:.status.loadBalancer.ingress[0].ip | tail -n1)"

  # We need to poll until the service comes up and to get IPs, this will return non-zero codes for a while
  set +e
  aws_ip=`curl --max-time .1 --connect-timeout .1 http://169.254.169.254/latest/meta-data/public-hostname`
  gcp_ip=`curl --max-time .1 --connect-timeout .1 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip`

  for local_ip in `ip -br addr  | awk '{print $3}' | awk -F/ '{print $1}' | grep -v "127.0.0.1"`; do
    curl --max-time .1 --connect-timeout .1 -L ${local_ip}:${jupyter_port} && break
    echo curl --max-time .1 --connect-timeout .1 -L ${local_ip}:${jupyter_port} && break
  done
  if [ "${?}" != "0" ]; then
    echo "WARNING: Could not determine local IP"
    local_ip=""
  fi
  set -e

  if [ "${gcp_ip}" != "" ]; then
    IP=${gcp_ip}
  elif [ "${aws_ip}" != "" ]; then
    IP=${aws_ip}
  else
    IP=${local_ip}
  fi

  echo -e "\nJupyter default password: dask"
  echo "Jupyter located via NodePort at: http://${IP}:${jupyter_port}"
  echo "Jupyter located via External IP at: http://${jupyter_ip}"
  echo "Dask located via NodePort at: http://${IP}:${dask_port}"
  echo "Dask located via External IP at: http://${dask_ip}"
}


get_opts ${@}
tear_down
build_image
stand_up
copy_config
get_url

