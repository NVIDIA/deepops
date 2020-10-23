#!/usr/bin/env bash

# can be run standalone with: curl -sL git.io/deepops | bash
# or: curl -sL git.io/deepops | bash -s -- 19.07

# DeepOps branch to setup
DEEPOPS_TAG="${1:-master}"
JENKINS="${JENKINS:-}" # Used to signal we are in a Jenkins testing environment and need virtualenv

. /etc/os-release

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${SCRIPT_DIR}/.." || echo "Could not cd to repository root"

# Pinned Ansible version
ANSIBLE_OK="2.7.8"
ANSIBLE_VERSION="2.9.5"
PROXY_USE=`grep -v ^# ${SCRIPT_DIR}/deepops/proxy.sh | grep -v ^$ | wc -l`
PIP="${PIP:-pip3}"

JINJA2_VERSION="${JINJA2_VERSION:-2.11.1}"

as_sudo(){
    if [ $PROXY_USE -gt 0 ]; then
        cmd="sudo -H bash -c '. ${SCRIPT_DIR}/deepops/proxy.sh && $1'"
    else
        cmd="sudo bash -c '$1'"
    fi
    eval $cmd
}

as_user(){
    if [ $PROXY_USE -gt 0 ]; then
        cmd="bash -c '. ${SCRIPT_DIR}/deepops/proxy.sh && $1'"
    else
        cmd="bash -c '$1'"
    fi
    eval $cmd
}

# Install Software
case "$ID" in
    rhel*|centos*)
        # Enable EPEL (required for Pip)
        as_sudo 'yum -y install epel-release'

        # Install pip
        if ! which ${PIP} >/dev/null 2>&1; then
            echo "Installing python3 pip..."
            as_sudo 'yum -y install python36-pip' >/dev/null
        fi
        ${PIP} --version

        # Use virtualenv vs system pip when we're running under Jenkins
        if ! [ -z "${VIRT_DIR}" ] && ! [ -z "${JENKINS}" ]; then
            # Install python3 virtualenv
            type virtualenv >/dev/null 2>&1
            if [ $? -ne 0 ] ; then
                as_sudo 'yum -y install python3-virtualenv' >/dev/null
            fi
            # Create virtual environment
            virtualenv env
            # Use virtual environment
            . env/bin/activate
            # Upgrade jinja2
            as_user "${PIP} install --upgrade Jinja2==${JINJA2_VERSION}"
            # Install ansible
            as_user "${PIP} install ansible==${ANSIBLE_VERSION}"
            # Install netaddr
            as_user "${PIP} install netaddr"
            # Install ruamel.yaml
            as_user "${PIP} install ruamel.yaml"
            # Install python3 mysql client library
            as_user "${PIP} install PyMySQL"
        fi

        # Ensure Jinja2 is updated
        echo "Upgrading jinja2"
        as_sudo "${PIP} install --upgrade Jinja2==${JINJA2_VERSION}"

        # Check Ansible version and install with pip
        if ! which ansible >/dev/null 2>&1; then
            as_sudo "${PIP} install ansible==${ANSIBLE_VERSION}" >/dev/null
        else
            current_version=$(ansible --version | head -n1 | awk '{print $2}')
            if ! python3 -c "from distutils.version import LooseVersion; print(LooseVersion('$ANSIBLE_OK') <= LooseVersion('$current_version'))" | grep True >/dev/null 2>&1 ; then
                echo "Unsupported version of Ansible: ${current_version}"
                echo "Version must be ${ANSIBLE_OK} or greater"
                exit 1
            fi
            if python3 -c "from distutils.version import LooseVersion; print(LooseVersion('$current_version') < LooseVersion('$ANSIBLE_VERSION'))" | grep True >/dev/null 2>&1 ; then
                echo "Upgrading Ansible version to ${ANSIBLE_VERSION}..."
                as_sudo "${PIP} install ansible==${ANSIBLE_VERSION}" >/dev/null
            fi
        fi
        ansible --version | head -1

        # Install python3-netaddr
        python3 -c 'import netaddr' >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "Installing Python dependencies..."
            as_sudo 'yum -y install python36 python36-netaddr' >/dev/null
            as_sudo 'ln -s /usr/bin/python36 /usr/bin/python3'
        fi

        # Install git
        type git >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "Installing git..."
            as_sudo 'yum -y install git' >/dev/null
        fi
        git --version

        # Install IPMItool
        type ipmitool >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "Installing IPMITool..."
            as_sudo 'yum -y install ipmitool' >/dev/null
        fi
        ipmitool -V

        # Install wget
        if ! which wget >/dev/null 2>&1; then
            echo "Installing wget..."
            as_sudo 'yum -y install wget' >/dev/null
        fi
        wget --version | head -1

        # Install sshpass
        if ! which sshpass >/dev/null 2>&1; then
            echo "Installing sshpass..."
            as_sudo 'yum -y install sshpass' >/dev/null
        fi
        sshpass -V | head -1
        ;;
    ubuntu*)
	# No interactive prompts from apt during this process
	export DEBIAN_FRONTEND=noninteractive
        # Update apt cache
        echo "Updating apt cache..."
        as_sudo 'apt-get update' >/dev/null

        # Install repo tool
        type apt-add-repository >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            as_sudo 'apt-get -y install software-properties-common' >/dev/null
        fi

        # Install sshpass
        type sshpass >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            as_sudo 'apt-get -y install sshpass' >/dev/null
        fi

        # Install pip
        if ! which ${PIP} >/dev/null 2>&1; then
            echo "Installing pip..."
            as_sudo 'apt-get -y install python3-pip' >/dev/null
        fi
        ${PIP} --version

        # Install setuptools
        if ! dpkg -l python3-setuptools >/dev/null 2>&1; then
            echo "Installing setuptools..."
            as_sudo 'apt-get -y install python3-setuptools' >/dev/null
        fi

        # Use virtualenv vs system pip when we're running under Jenkins
        if ! [ -z "${VIRT_DIR}" ] && ! [ -z "${JENKINS}" ]; then
            # Install python3 python3-virtualenv
            type virtualenv >/dev/null 2>&1
            if [ $? -ne 0 ] ; then
                as_sudo 'apt-get -y install virtualenv' >/dev/null
            fi
            # Create virtual environment
            virtualenv env
            # Use virtual environment
            . env/bin/activate
            # Install Ansible
            as_user "${PIP} install ansible==${ANSIBLE_VERSION}"
            # Install netaddr
            as_user "${PIP} install netaddr" >/dev/null
            # Install python3 mysql client library
            as_user "${PIP} install PyMySQL"
        fi

        # Check Ansible version and install with pip
        if ! which ansible >/dev/null 2>&1; then
            as_sudo "${PIP} install ansible==${ANSIBLE_VERSION}" >/dev/null
        else
            current_version=$(ansible --version | head -n1 | awk '{print $2}')
            if ! python3 -c "from distutils.version import LooseVersion; print(LooseVersion('$ANSIBLE_OK') <= LooseVersion('$current_version'))" | grep True >/dev/null 2>&1 ; then
                echo "Unsupported version of Ansible: ${current_version}"
                echo "Version must be ${ANSIBLE_OK} or greater"
                exit 1
            fi
            if python3 -c "from distutils.version import LooseVersion; print(LooseVersion('$current_version') < LooseVersion('$ANSIBLE_VERSION'))" | grep True >/dev/null 2>&1 ; then
                echo "Upgrading Ansible version to ${ANSIBLE_VERSION}..."
                as_sudo "${PIP} install ansible==${ANSIBLE_VERSION}" >/dev/null
            fi
        fi
        ansible --version | head -1

        # Install python3-netaddr
        python3 -c 'import netaddr' >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "Installing Python dependencies..."
            as_sudo 'apt-get -y install python3-netaddr' >/dev/null
        fi

        # Install git
        type git >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "Installing git..."
            as_sudo 'apt-get -y install git' >/dev/null
        fi
        git --version

        # Install IPMItool
        type ipmitool >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "Installing IPMITool..."
            as_sudo 'apt-get -y install ipmitool' >/dev/null
        fi
        ipmitool -V

        # Install wget
        if ! which wget >/dev/null 2>&1; then
        echo "Installing wget..."
            as_sudo 'apt-get -y install wget' >/dev/null
        fi
        wget --version | head -1
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        echo "Please install Ansible, Git, and python3-netaddr manually"
        ;;
esac

if ! grep -i deepops README.md >/dev/null 2>&1 ; then
    cd "${SCRIPT_DIR}"
    if ! test -d deepops ; then
        if [ $PROXY_USE -gt 0 ]; then
            . ${SCRIPT_DIR}/deepops/proxy.sh && git clone --branch ${DEEPOPS_TAG} https://github.com/NVIDIA/deepops.git
        else
            git clone --branch ${DEEPOPS_TAG} https://github.com/NVIDIA/deepops.git
        fi
    fi
    cd deepops
fi

# Install Ansible Galaxy roles
ansible-galaxy --version >/dev/null 2>&1
if [ $? -eq 0 ] ; then
    echo "Updating Ansible Galaxy roles..."
    if [ $PROXY_USE -gt 0 ]; then
        . ${SCRIPT_DIR}/deepops/proxy.sh && ansible-galaxy install --force -r roles/requirements.yml >/dev/null
    else
        ansible-galaxy install --force -r roles/requirements.yml >/dev/null
    fi


else
    echo "ERROR: Unable to install Ansible Galaxy roles"
fi

# Update submodules
git status >/dev/null 2>&1
if [ $? -eq 0 ] ; then
    if [ $PROXY_USE -gt 0 ]; then
        . ${SCRIPT_DIR}/deepops/proxy.sh && git submodule update --init
    else
        git submodule update --init
    fi
else
    echo "ERROR: Unable to update Git submodules"
fi

# Copy default configuration
CONFIG_DIR=${CONFIG_DIR:-./config}
if [ ! -d "${CONFIG_DIR}" ] ; then
    cp -rfp ./config.example "${CONFIG_DIR}"
    echo "Copied default configuration to ${CONFIG_DIR}"
else
    echo "Configuration directory '${CONFIG_DIR}' exists, not overwriting"
fi
