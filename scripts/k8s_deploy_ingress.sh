#!/bin/bash
set -x

# Get absolute path for script and root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/.."

# Allow overriding config dir to look in
config_dir=${DEEPOPS_CONFIG_DIR:-"${ROOT_DIR}/config"}
if [ ! -d "${config_dir}" ]; then
	echo "Can't find configuration in ${config_dir}"
	echo "Please set DEEPOPS_CONFIG_DIR env variable to point to config location"
	exit 1
fi

# Set up the ingress controller
if ! helm status nginx-ingress >/dev/null 2>&1; then
	helm install --name nginx-ingress --values "${config_dir}/helm/ingress.yml" stable/nginx-ingress
fi

for i in {1..10}; do
	echo "Check for ingress online... check ${i}"
	if kubectl get pods -l app=nginx-ingress,component=controller --no-headers | grep -i running;
	then
		break
	else
		sleep 30
	fi
done

# Show services
kubectl get services
