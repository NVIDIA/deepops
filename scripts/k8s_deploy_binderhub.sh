#!/bin/bash
# This deployment script is meant to be run on a K8S cluster provisioned using DeepOps
# The purpose of this script is to  deploy a namespace running BinderHub
# https://github.com/NVIDIA/deepops
# BUG: Due to current BinderHub implementation this deployment will utilize all nodes, not just GPU nodes (https://github.com/jupyterhub/binderhub/issues/712)
# TODO: Allow pushing images to DockerHub
# TODO: Allow pushing images to registry.local

# Define K8s/helm params
BINDERHUB_NAMESPACE=binderhub
BINDERHUB_VERSION=0.2.0-1eac3a0
JUPYTERHUB_CHART_REPO=https://jupyterhub.github.io/helm-chart
BINDERHUB_CHART_NAME=jupyterhub/binderhub
pod_count=5 # Currently we need 5 pods to be running for BinderHub, this may change in the future


# Define the configuration files
secret_file=config/helm/binderhub-secret.yml
config_file=config/helm/binderhub-config.yml
sed_inline="-i" # Default to modifying config files unless user specifies -c


function help_me() {
  echo "Usage:"
  echo "-h    This message."
  echo "-c    Don't modify the config files (excluding hub_url)"
  echo "-n    Kubernetes namespace"
}


function get_opts() {
while getopts "cn:t:h" option; do
  case $option in
    n)
      BINDERHUB_NAMESPACE=$OPTARG
      ;;
    t)
      docker_local_token=$OPTARG
      ;;
    c)
      sed_inline=""
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
if [ -z "${BINDERHUB_NAMESPACE}" ]; then
    BINDERHUB_NAMESPACE="binderhub"
fi
}


function make_config() {
  # Generate a secure hex used for Jupyterhub
  hex1=`openssl rand -hex 32`
  hex2=`openssl rand -hex 32`

  # Update configuration files with username/password/secrets
  sed ${sed_inline} "s/apiToken:.*/apiToken: ${hex1}/g" ${secret_file}
  sed ${sed_inline} "s/secretToken:.*/secretToken: ${hex2}/g" ${secret_file}
}


function tear_down() {
  # Delete existing resources
  helm list ${BINDERHUB_NAMESPACE} | grep ${BINDERHUB_NAMESPACE} 2> /dev/null 1> /dev/null
  if [ "${?}" == "0" ]; then
    read -r -p "Helm resources already exist, would you  like to delete them? (yes/no)" response
    case "$response" in
      [yY][eE][sS]|[yY])
        helm delete --purge ${BINDERHUB_NAMESPACE}
        sleep 2
        ;;
      *)
        echo "Quitting install"
        exit
        ;;
    esac
  fi

  kubectl get ns ${BINDERHUB_NAMESPACE} 2> /dev/null 1> /dev/null
  if [ "${?}" == "0" ]; then
    read -r -p "Kubernetes resources already exist, would you  like to delete them? (yes/no)" response
    case "$response" in
      [yY][eE][sS]|[yY])
        kubectl delete ns ${BINDERHUB_NAMESPACE}
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
  # Add BinderHub chart repo
  helm repo add jupyterhub ${JUPYTERHUB_CHART_REPO}
  helm repo update

  # Check for Rook dependency
  kubectl get storageclass 2>&1 | grep "No resources found." >/dev/null 2>&1
  if [ $? -eq 0 ] ; then
    echo "No storageclass found"
    echo "To provision Ceph storage, run: ./scripts/k8s_deploy_rook.sh"
    exit 1
  fi

  # Check for default DeepOps LoadBalancer installed via Helm
  helm list| grep metallb >/dev/null 2>&1
  if [ $? != 0 ]; then
    echo "Did not find default DeepOps loadbalancer installation (MetalLB)"
    echo "Please make sure there is a load balancer configured with a valid IP range. Failure to do so may result with broken Jupyter Notebook links. This must be done before the BinderHub install"
    echo "If you are running this in the cloud you do not need to manually configure a LoadBalancer and can ignore  this message"
  fi

  # Create namespace
  kubectl create ns ${BINDERHUB_NAMESPACE}
  sleep 1 # XXX: If we don't wait a little bit the next command will fail

  # Install Binderhub
  helm install ${BINDERHUB_CHART_NAME} --version=${BINDERHUB_VERSION}  --name=${BINDERHUB_NAMESPACE} --namespace=${BINDERHUB_NAMESPACE} -f ${secret_file} -f ${config_file}
  while [ `kubectl -n ${BINDERHUB_NAMESPACE} get pods | grep Running | wc -l` -lt ${pod_count} ]; do
    sleep 1
  done
  sleep 1 # Give services time to start after pods are created

  # Connect BinderHub to running JupyterHub instance as per the docs
  get_url

  sed -i "s~.*hub_url:.*~    hub_url: http://${IP}:${jupyterhub_port}~g" ${config_file} # XXX: Always modify this, because it will change
  helm upgrade ${BINDERHUB_NAMESPACE} ${BINDERHUB_CHART_NAME} --version=${BINDERHUB_VERSION}  -f ${secret_file} -f ${config_file}
}


function get_url() {
  # Output connection info
  jupyterhub_ip=`kubectl -n ${BINDERHUB_NAMESPACE} get svc proxy-public -ocustom-columns=:.status.loadBalancer.ingress[0].ip | tail -n1`
  jupyterhub_port="$(kubectl -n ${BINDERHUB_NAMESPACE} get svc proxy-public -ocustom-columns=:.spec.ports[0].nodePort | tail -n1)"
  binderhub_ip=`kubectl -n ${BINDERHUB_NAMESPACE} get svc binder -ocustom-columns=:.status.loadBalancer.ingress[0].ip | tail -n1`
  binderhub_port=`kubectl -n ${BINDERHUB_NAMESPACE} get svc binder -ocustom-columns=:.spec.ports[0].nodePort | tail -n1`

  aws_ip=`curl --max-time .1 --connect-timeout .1 http://169.254.169.254/latest/meta-data/public-hostname`
  gcp_ip=`curl --max-time .1 --connect-timeout .1 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip`

  for local_ip in `ip -br addr  | awk '{print $3}' | awk -F/ '{print $1}'`; do
    curl --max-time .1 --connect-timeout .1 -L ${local_ip}:${binderhub_port} && break
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

  echo -e "\nBinderHub NodePort located at: http://${IP}:${binderhub_port}"
  echo "BinderHub External IP located at: http://${binderhub_ip}"
}


get_opts ${@}
make_config
tear_down
stand_up
get_url

