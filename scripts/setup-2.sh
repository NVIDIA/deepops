#!/usr/bin/env bash

# Can be run standalone with: curl -sL git.io/deepops | bash
# or: curl -sL git.io/deepops | bash -s -- 19.07

DEEPOPS_TAG="${1:-master}"                      # DeepOps branch to setup
VENV_DIR="${VENV_DIR:-/opt/deepops/env}"        # Path to python virtual environment
ANSIBLE_VERSION="2.9.5"                         # Ansible version to install
ANSIBLE_OK="2.7.8"                              # Oldest allowed Ansible version
JINJA2_VERSION="${JINJA2_VERSION:-2.11.1}"      # Jinja2 required version

###

. /etc/os-release

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${SCRIPT_DIR}/.." || echo "Could not cd to repository root"

DEPS_DEB=(git python3-virtualenv sshpass wget)
DEPS_RPM=(git python3-virtualenv sshpass wget)
PIP="${PIP:-pip3}"
PROXY_USE=`grep -v ^# ${SCRIPT_DIR}/deepops/proxy.sh 2>/dev/null | grep -v ^$ | wc -l`

# No interactive prompts from Apt during this process
export DEBIAN_FRONTEND=noninteractive

# Exit if run as root
if [ $(id -u) -eq 0 ] ; then
    echo "Please run as a regular user"
    exit
fi

# Proxy wrapper
as_sudo(){
    if [ $PROXY_USE -gt 0 ]; then
        cmd="sudo -H bash -c '. ${SCRIPT_DIR}/deepops/proxy.sh && $@'"
    else
        cmd="sudo bash -c '$@'"
    fi
    eval $cmd
}

# Proxy wrapper
as_user(){
    if [ $PROXY_USE -gt 0 ]; then
        cmd="bash -c '. ${SCRIPT_DIR}/deepops/proxy.sh && $@'"
    else
        cmd="bash -c '$@'"
    fi
    eval $cmd
}

# Install software dependencies
case "$ID" in
    rhel*|centos*)
        # Enable EPEL (required for Pip)
        EPEL_VERSION="$(echo ${VERSION_ID} | sed  's/^[^0-9]*//;s/[^0-9].*$//')"
        EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${EPEL_VERSION}.noarch.rpm"
        as_sudo "yum -yq install ${EPEL_URL}"

        as_sudo "yum -yq install ${DEPS_RPM[@]}"
        ;;
    ubuntu*)
        as_sudo 'apt-get -q update'
        as_sudo "apt -yq install ${DEPS_RPM[@]}"
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        echo "Please install ${DEPS_RPM[@]} manually"
        ;;
esac

# Create virtual environment and install python dependencies
sudo mkdir -p "${VENV_DIR}"
sudo chown -R $(id -u):$(id -g) "${VENV_DIR}"
deactivate &> /dev/null
virtualenv --python=python3 -q "${VENV_DIR}"
. "${VENV_DIR}/bin/activate"
as_user "${PIP} install -q --upgrade \
    ansible==${ANSIBLE_VERSION} \
    Jinja2==${JINJA2_VERSION} \
    netaddr \
    ruamel.yaml \
    PyMySQL"

# Clone DeepOps git repo if running standalone
if ! grep -i deepops README.md >/dev/null 2>&1 ; then
    cd "${SCRIPT_DIR}"
    if ! test -d deepops ; then
        as_user git clone --branch ${DEEPOPS_TAG} https://github.com/NVIDIA/deepops.git
    fi
    cd deepops
fi

# Install Ansible Galaxy roles
if command -v ansible-galaxy &> /dev/null ; then
    echo "Updating Ansible Galaxy roles..."
    as_user ansible-galaxy collection install --force -r roles/requirements.yml >/dev/null
    as_user ansible-galaxy role install --force -r roles/requirements.yml >/dev/null
else
    echo "ERROR: Unable to install Ansible Galaxy roles, 'ansible-galaxy' command not found"
fi

# Update submodules
if command -v git &> /dev/null ; then
    as_user git submodule update --init
else
    echo "ERROR: Unable to update Git submodules, 'git' command not found"
fi

# Copy default configuration
CONFIG_DIR=${CONFIG_DIR:-./config}
if [ ! -d "${CONFIG_DIR}" ] ; then
    cp -rfp ./config.example "${CONFIG_DIR}"
    echo "Copied default configuration to ${CONFIG_DIR}"
else
    echo "Configuration directory '${CONFIG_DIR}' exists, not overwriting"
fi

echo "*** Setup complete ***"
echo "To use Ansible, run: source ${VENV_DIR}/bin/activate"
echo
