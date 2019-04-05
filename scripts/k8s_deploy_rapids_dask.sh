#!/bin/bash
# In order for this deployment to properly work across your cluster you will need to build the customer Docker image and push it out to your local Docker repository

# This script will create a dask cluster including 1 Jupyter container,  1 Dask  scheduler, and N Dask workers.
# The Dask workers can be scaled from  the K8S command line using `kubectl scale` commands or through jupyter using dask_kubernetes commands
# See the included sample notebooks for details.

# Global K8S/Helm variables
RAPIDS_DASK_DOCKER_REPO="${RAPIDS_DASK_DOCKER_REPO:-https://github.com/supertetelman/k8s-rapids-dask.git}"
DASK_CHART_NAME=stable/dask
DOCKER_REGISTRY=registry.local

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
}


function get_opts() {
while getopts "n:d:ph" option; do
  case $option in
    n)
      RAPIDS_NAMESPACE=$OPTARG
      ;;
    d)
      DASK_IMAGE=$OPTARG
      ;;
   p)
      PUSH_IMAGE=true
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
RAPIDS_TMP_BUILD_DIR="${RAPIDS_TMP_BUILD_DIR:-tmp-rapids-build}"
DASK_IMAGE="${DASK_IMAGE:-dask-rapids}"
}


function build_image() {
  echo "Building custom dask/rapids image: ${DASK_IMAGE}"
  ls "${RAPIDS_TMP_BUILD_DIR}"
  if [ "${?}" == "0" ]; then
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
  git clone "${RAPIDS_DASK_DOCKER_REPO}" "${RAPIDS_TMP_BUILD_DIR}"
  pushd "${RAPIDS_TMP_BUILD_DIR}"

  # Build the docker image
  docker build -t ${DASK_IMAGE} .

  popd
  rm -rf "${RAPIDS_TMP_BUILD_DIR}"
  if [ "${DOCKER_PUSH}" != "" ]; then
    docker tag ${DASK_IMAGE} ${DOCKER_REGISTRY}/${DASK_IMAGE}
    docker push ${DOCKER_REGISTRY}/${DASK_IMAGE}
  fi
}


function tear_down() {
  # Delete existing resources
  helm list ${RAPIDS_NAMESPACE} | grep ${RAPIDS_NAMESPACE} 2> /dev/null 1> /dev/null
  if [ "${?}" == "0" ]; then
    read -r -p "Helm resources already exist, would you  like to delete them? (yes/no)" response
    case "$response" in
      [yY][eE][sS]|[yY])
        helm delete --purge ${RAPIDS_NAMESPACE}
        sleep 2
        ;;
      *)
        echo "Quitting install"
        exit
        ;;
    esac
  fi

  kubectl get ns ${RAPIDS_NAMESPACE} 2> /dev/null 1> /dev/null
  if [ "${?}" == "0" ]; then
    read -r -p "Kubernetes resources already exist, would you  like to delete them? (yes/no)" response
    case "$response" in
      [yY][eE][sS]|[yY])
        kubectl delete ns ${RAPIDS_NAMESPACE}
        sleep 2
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
  helm install -n ${RAPIDS_NAMESPACE} --namespace ${RAPIDS_NAMESPACE} --values config/helm/rapids-dask.yml ${DASK_CHART_NAME}
  kubectl create -n ${RAPIDS_NAMESPACE}  -f config/k8s/rapids-dask-sa.yml
  # kubectl create -f  config/k8s/rapids-dask-autoscale.yml # XXX: Optional install
  while [ `kubectl -n ${RAPIDS_NAMESPACE} get pods | grep Running | wc -l` != ${pod_count} ]; do
    sleep 1
  done
}


function copy_config() {
  echo "Copying dask-worker yaml file into running jupyter container"
  kubectl -n ${RAPIDS_NAMESPACE} scale deployment ${RAPIDS_NAMESPACE}-dask-worker --replicas=1
  # Wait for containers to initialize
  while [ `kubectl -n ${RAPIDS_NAMESPACE} get pods | grep Running | wc -l` != ${pod_count_scale} ]; do
    sleep 1
  done

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
  kubectl -n ${RAPIDS_NAMESPACE} scale deployment ${RAPIDS_NAMESPACE}-dask-worker --replicas=0
  # Wait for containers to initialize
  while [ `kubectl -n ${RAPIDS_NAMESPACE} get pods | grep Running | wc -l` != ${pod_count_scale_down} ]; do
    sleep 1
  done
}

function get_url() {
  # Output connection info
  jupyter_ip="$(kubectl -n ${RAPIDS_NAMESPACE} get svc ${RAPIDS_NAMESPACE}-dask-jupyter -ocustom-columns=:.status.loadBalancer.ingress[0].ip | tail -n1)"
  jupyter_port="$(kubectl -n ${RAPIDS_NAMESPACE} get svc ${RAPIDS_NAMESPACE}-dask-jupyter -ocustom-columns=:.spec.ports[0].nodePort | tail -n1)"
  dask_port="$(kubectl -n ${RAPIDS_NAMESPACE} get svc ${RAPIDS_NAMESPACE}-dask-jupyter -ocustom-columns=:.spec.ports[0].nodePort | tail -n1)"
  dask_ip="$(kubectl -n ${RAPIDS_NAMESPACE} get svc ${RAPIDS_NAMESPACE}-dask-scheduler -ocustom-columns=:.status.loadBalancer.ingress[0].ip | tail -n1)"
  
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

  if [ "${gcp_ip}" != "" ]; then
    IP=${gcp_ip}
  elif [ "${aws_ip}" != "" ]; then
    IP=${aws_ip}
  else
    IP=${local_ip}
  fi

  echo -e "\nJupyter default password: dask"
  echo "Jupyter located via NodePort at: ${IP}:${jupyter_port}"
  echo "Jupyter located via External IP at: ${jupyter_ip}"
  echo "Dask located via NodePort at: ${IP}:${dask_port}"
  echo "Dask located via External IP at: ${dask_ip}"
}


get_opts ${@}
tear_down
build_image
stand_up
copy_config
get_url
