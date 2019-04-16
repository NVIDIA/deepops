#!/bin/bash
set -x

# Get absolute path for script and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."

# Allow overriding the app name with an env var
app_name="${NGINX_INGRESS_APP_NAME:-nginx-ingress}"

# Allow overriding config dir to look in
config_dir=${DEEPOPS_CONFIG_DIR:-"${ROOT_DIR}/config"}

if [ ! -d "${config_dir}" ]; then
	echo "Can't find configuration in ${config_dir}"
	echo "Please set DEEPOPS_CONFIG_DIR env variable to point to config location"
	exit 1
fi

kubectl version
if [ $? -ne 0 ] ; then
    echo "Unable to talk to Kubernetes API"
    exit 1
fi

# Set up the ingress controller
if ! helm status "${app_name}" >/dev/null 2>&1; then
	helm install --name "${app_name}" --values "${config_dir}/helm/ingress.yml" stable/nginx-ingress
fi

kubectl wait --for=condition=Ready -l "app=${app_name},component=controller" --timeout=90s pod
