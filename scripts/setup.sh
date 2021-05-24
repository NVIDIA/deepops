#!/bin/bash --init-file

# DeepOps setup/bootstrap script
#   This script installs required dependencies on a system so it can run Ansible
#   and initializes the DeepOps directory
#
# Can be run standalone with: curl -sL git.io/deepops | bash
#                         or: curl -sL git.io/deepops | bash -s -- 19.07

# Configuration
ANSIBLE_VERSION="${ANSIBLE_VERSION:-2.9.21}"     # Ansible version to install
ANSIBLE_TOO_NEW="${ANSIBLE_TOO_NEW:-2.10.0}"    # Ansible version too new
CONFIG_DIR="${CONFIG_DIR:-./config}"            # Default configuration directory location
DEEPOPS_TAG="${1:-master}"                      # DeepOps branch to set up
JINJA2_VERSION="${JINJA2_VERSION:-2.11.1}"      # Jinja2 required version
PIP="${PIP:-pip3}"                              # Pip binary to use
PYTHON_BIN="${PYTHON_BIN:-/usr/bin/python3}"    # Python3 path
VENV_DIR="${VENV_DIR:-/opt/deepops/env}"        # Path to python virtual environment to create

###

# Set distro-specific variables
. /etc/os-release

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

DEPS_DEB=(git virtualenv python3-virtualenv sshpass wget)
DEPS_EL7=(git libselinux-python3 python-virtualenv python3-virtualenv sshpass wget)
DEPS_EL8=(git python3-libselinux python3-virtualenv sshpass wget)
EPEL_VERSION="$(echo ${VERSION_ID} | sed  's/^[^0-9]*//;s/[^0-9].*$//')"
EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${EPEL_VERSION}.noarch.rpm"
PROXY_USE=`grep -v ^# ${SCRIPT_DIR}/deepops/proxy.sh 2>/dev/null | grep -v ^$ | wc -l`

# Disable interactive prompts from Apt
export DEBIAN_FRONTEND=noninteractive

# Exit if run as root
if [ $(id -u) -eq 0 ] ; then
    echo "Please run as a regular user"
    exit
fi

# Proxy wrapper
as_sudo(){
    if [ $PROXY_USE -gt 0 ] ; then
        cmd="sudo -H bash -c '. ${SCRIPT_DIR}/deepops/proxy.sh && $@'"
    else
        cmd="sudo bash -c '$@'"
    fi
    eval $cmd
}

# Proxy wrapper
as_user(){
    if [ $PROXY_USE -gt 0 ] ; then
        cmd="bash -c '. ${SCRIPT_DIR}/deepops/proxy.sh && $@'"
    else
        cmd="bash -c '$@'"
    fi
    eval $cmd
}

# Install software dependencies
case "$ID" in
    rhel*|centos*)
        as_sudo "yum -y -q install ${EPEL_URL} |& grep -v 'Nothing to do'"       # Enable EPEL (required for sshpass package)
        case "$EPEL_VERSION" in
            7)
                as_sudo "yum -y -q install ${DEPS_EL7[@]}"
                ;;
            8)
                as_sudo "yum -y -q install ${DEPS_EL8[@]}"
                ;;
            esac
        ;;
    ubuntu*)
        as_sudo "apt-get -q update"
        as_sudo "apt-get -yq install ${DEPS_DEB[@]}"
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        echo "Please install ${DEPS_RPM[@]} manually"
        ;;
esac

# Create virtual environment and install python dependencies
if command -v virtualenv &> /dev/null ; then
    sudo mkdir -p "${VENV_DIR}"
    sudo chown -R $(id -u):$(id -g) "${VENV_DIR}"
    deactivate nondestructive &> /dev/null
    virtualenv -q --python="${PYTHON_BIN}" "${VENV_DIR}"
    . "${VENV_DIR}/bin/activate"
    as_user "${PIP} install -q --upgrade pip"

    # Check for any installed ansible pip package
    if pip show ansible 2>&1 >/dev/null; then
        current_version=$(pip show ansible | grep Version | awk '{print $2}')
	echo "Current version of Ansible is ${current_version}"
	if "${PYTHON_BIN}" -c "from distutils.version import LooseVersion; print(LooseVersion('$current_version') >= LooseVersion('$ANSIBLE_TOO_NEW'))" | grep True 2>&1 >/dev/null; then
            echo "Ansible version ${current_version} too new for DeepOps"
	    echo "Please uninstall any ansible, ansible-base, and ansible-core packages and re-run this script"
	    exit 1
	fi
	if "${PYTHON_BIN}" -c "from distutils.version import LooseVersion; print(LooseVersion('$current_version') < LooseVersion('$ANSIBLE_VERSION'))" | grep True 2>&1 >/dev/null; then
	    echo "Ansible will be upgraded from ${current_version} to ${ANSIBLE_VERSION}"
	fi
    fi

    as_user "${PIP} install -q --upgrade \
        ansible==${ANSIBLE_VERSION} \
        Jinja2==${JINJA2_VERSION} \
        netaddr \
        ruamel.yaml \
        PyMySQL \
        selinux"
else
    echo "ERROR: Unable to create Python virtual environment, 'virtualenv' command not found"
    exit 1
fi

# Clone DeepOps git repo if running standalone
if ! (cd "${SCRIPT_DIR}/.." && grep -i deepops README.md >/dev/null 2>&1 ) ; then
    if command -v git &> /dev/null ; then
        if ! test -d deepops ; then
            as_user git clone --branch ${DEEPOPS_TAG} https://github.com/NVIDIA/deepops.git
        fi
        cd deepops
    else
        echo "ERROR: Unable to check out DeepOps git repo, 'git' command not found"
        exit
    fi
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
if grep -i deepops README.md >/dev/null 2>&1 ; then
    if [ ! -d "${CONFIG_DIR}" ] ; then
        cp -rfp ./config.example "${CONFIG_DIR}"
        echo "Copied default configuration to ${CONFIG_DIR}"
    else
        echo "Configuration directory '${CONFIG_DIR}' exists, not overwriting"
    fi
fi

# Add Ansible virtual env to PATH when using Bash
if [ -f "${VENV_DIR}/bin/activate" ] ; then
    . "${VENV_DIR}/bin/activate"
    ansible localhost -m lineinfile -a "path=$HOME/.bashrc create=yes mode=0644 backup=yes line='source ${VENV_DIR}/bin/activate'"
fi

echo
echo "*** Setup complete ***"
echo "To use Ansible, run: source ${VENV_DIR}/bin/activate"
echo
