#!/bin/bash
set -x

# Get absolute path for script and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."
CHART_VERSION="1.22.1"

./scripts/install_helm.sh

# Allow overriding the app name with an env var
app_name="${NGINX_INGRESS_APP_NAME:-nginx-ingress}"

# Allow overriding config dir to look in
config_dir=${DEEPOPS_CONFIG_DIR:-"${ROOT_DIR}/config"}

if [ ! -d "${config_dir}" ]; then
	echo "Can't find configuration in ${config_dir}"
	echo "Please set DEEPOPS_CONFIG_DIR env variable to point to config location"
	exit 1
fi

if ! kubectl version ; then
    echo "Unable to talk to Kubernetes API"
    exit 1
fi

# We need to dynamically set up Helm args, so let's use an array
helm_arguments=("--version" "${CHART_VERSION}"
		"--values" "${config_dir}/helm/ingress.yml"
)


if [ "${NGINX_INGRESS_CONTROLLER_REPO}" ]; then
	helm_arguments+=("--set-string" "controller.image.repository=${NGINX_INGRESS_CONTROLLER_REPO}")
fi
if [ "${NGINX_INGRESS_BACKEND_REPO}" ]; then
	helm_arguments+=("--set-string" "defaultBackend.image.repository=${NGINX_INGRESS_BACKEND_REPO}")
fi

# Set up the ingress controller
if ! helm status "${app_name}" >/dev/null 2>&1; then
	helm install "${app_name}" "${helm_arguments[@]}" stable/nginx-ingress
fi

kubectl wait --for=condition=Ready -l "app=${app_name},component=controller" --timeout=180s pod
