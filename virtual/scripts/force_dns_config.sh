#!/bin/bash
set -ex

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPT_DIR}/../.."

# Move working directory to root of DeepOps repo
cd "${ROOT_DIR}" || exit 1

# Configure resolv.conf by hand
FORCE_DNS_ADDRESS=${FORCE_DNS_ADDRESS:-8.8.8.8}
ansible -b -v -i "${ROOT_DIR}/virtual/config/inventory" -m raw -a "grep '${FORCE_DNS_ADDRESS}' /etc/resolv.conf || rm /etc/resolv.conf" all
ansible -b -v -i "${ROOT_DIR}/virtual/config/inventory" -m raw -a "grep '${FORCE_DNS_ADDRESS}' /etc/resolv.conf || echo 'nameserver ${FORCE_DNS_ADDRESS}' > /etc/resolv.conf" all

# Stop systemd-resolved
ansible -b -v -i "${ROOT_DIR}/virtual/config/inventory" -m raw -a "systemctl stop systemd-resolved" all || echo "Couldn't stop systemd-resolved"
 
# Bootstrap python
ansible-playbook -v -i "${ROOT_DIR}/virtual/config/inventory" playbooks/bootstrap-python.yml

# Configure DNS for real
ansible-playbook -v -i "${ROOT_DIR}/virtual/config/inventory" \
	-e "@${ROOT_DIR}/virtual/vars_files/dns_config.yml" playbooks/dns-config.yml
