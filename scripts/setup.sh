#!/usr/bin/env bash

# can be run standalone with: curl -sL git.io/deepops | bash

. /etc/os-release

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${SCRIPT_DIR}/.." || echo "Could not cd to repository root"

# Pinned Ansible version
ANSIBLE_OK="2.7.8"
ANSIBLE_VERSION="2.7.11"
ANSIBLE_REPO_VER="2.7"

as_sudo(){
   cmd="sudo bash -c '. ${SCRIPT_DIR}/proxy.sh && $1'"
   echo $cmd
   eval $cmd
}

# Install Software
case "$ID" in
    rhel*|centos*)
        # Enable EPEL (required for Pip)
        as_sudo  'yum -y install epel-release'

        # Install pip
        if ! which pip >/dev/null 2>&1; then
            echo "Installing pip..."
            as_sudo 'yum -y install python-pip' >/dev/null
        fi
        pip --version

        # Ensure Jinja2 is updated
        echo "Upgrading jinja2"
        as_sudo 'pip install --upgrade Jinja2'

        # Check Ansible version and install with pip
        if ! which ansible >/dev/null 2>&1; then
            ## as_sudo 'pip install ansible=="${ANSIBLE_VERSION}"'
            as_sudo 'pip install ansible==${ANSIBLE_VERSION}'
        else
            current_version=$(ansible --version | head -n1 | awk '{print $2}')
            if ! python -c "from distutils.version import LooseVersion; print LooseVersion('$ANSIBLE_OK') <= LooseVersion('$current_version')" | grep True >/dev/null 2>&1 ; then
                echo "Unsupported version of Ansible: ${current_version}"
                echo "Version must be ${ANSIBLE_OK} or greater"
                exit 1
            fi
        fi
        ansible --version | head -1

        # Install python-netaddr
        python -c 'import netaddr' >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "Installing Python dependencies..."
            as_sudo 'yum -y install python36 python-netaddr' >/dev/null
            sudo ln -s /usr/bin/python36 /usr/bin/python3
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
        if ! which pip >/dev/null 2>&1; then
            echo "Installing pip..."
            as_sudo 'apt-get -y install python-pip' >/dev/null
        fi
        pip --version

        # Install setuptools
        if ! dpkg -l python-setuptools >/dev/null 2>&1; then
            echo "Installing setuptools..."
            as_sudo 'apt-get -y install python-setuptools' >/dev/null
        fi

        # Check Ansible version and install with pip
        if ! which ansible >/dev/null 2>&1; then
            ## as_sudo 'pip install ansible=="${ANSIBLE_VERSION}"'
            as_sudo "pip install ansible==$ANSIBLE_VERSION"
        else
            current_version=$(ansible --version | head -n1 | awk '{print $2}')
            if ! python -c "from distutils.version import LooseVersion; print LooseVersion('$ANSIBLE_OK') <= LooseVersion('$current_version')" | grep True >/dev/null 2>&1 ; then
                echo "Unsupported version of Ansible: ${current_version}"
                echo "Version must be ${ANSIBLE_OK} or greater"
                exit 1
            fi
        fi
        ansible --version | head -1

        # Install python-netaddr
        python -c 'import netaddr' >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "Installing Python dependencies..."
            as_sudo 'apt-get -y install python-netaddr python3-netaddr' >/dev/null
        fi

        # Install git
        type git >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "Installing git..."
            as_sudo 'apt -y install git' >/dev/null
        fi
        git --version

        # Install IPMItool
        type ipmitool >/dev/null 2>&1
        if [ $? -ne 0 ] ; then
            echo "Installing IPMITool..."
            as_sudo 'apt -y install ipmitool' >/dev/null
        fi
        ipmitool -V

        # Install wget
        if ! which wget >/dev/null 2>&1; then
            echo "Installing wget..."
            as_sudo 'apt -y install wget' >/dev/null
        fi
        wget --version | head -1
        ;;
    *)
        echo "Unsupported Operating System $ID_LIKE"
        echo "Please install Ansible, Git, and python-netaddr manually"
        ;;
esac

if ! grep -i deepops README.md >/dev/null 2>&1 ; then
    cd "${SCRIPT_DIR}"
    if ! test -d deepops ; then
	    . ${SCRIPT_DIR}/proxy.sh && git clone https://github.com/NVIDIA/deepops.git
    fi
    cd deepops
fi

# Install Ansible Galaxy roles
ansible-galaxy --version >/dev/null 2>&1
if [ $? -eq 0 ] ; then
    ansible-galaxy install -r requirements.yml
else
    echo "ERROR: Unable to install Ansible Galaxy roles"
fi

# Update submodules
git status >/dev/null 2>&1
if [ $? -eq 0 ] ; then
	## . ${SCRIPT_DIR/proxy.sh && git submodule update --init
	git submodule update --init
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

# TODO: What if proxies already set via env
# update the config/group_vars/all.yml file for proxy config
if [ `grep -v ^# ${SCRIPT_DIR}/proxy.sh | grep -v ^$ | wc -l` -gt 0 ]; then
    o=config.example/group_vars/all.yml
    t=config/group_vars/all.yml 
    echo "Updating [$t] to use proxies"
    . ${SCRIPT_DIR}/proxy.sh && cat $o | sed -e "s|#PROXY_ENV|proxy_env:|g" \
	                                    -e "s|#NO_PROXY|no_proxy: $no_proxy|g" \
	                                    -e "s|#HTTP_PROXY|http_proxy: $http_proxy|g" \
	                                    -e "s|#HTTPS_PROXY|https_proxy: $https_proxy|g" > $t
fi
