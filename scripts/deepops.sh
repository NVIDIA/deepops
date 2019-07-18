#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${SCRIPT_DIR}/.." || echo "Could not cd to repository root"

config=$(mktemp)

cat <<EOF > ${config}
#ENROOT_LOGIN_SHELL=/bin/bash
environ() {
    env
    echo "LANG=C.UTF-8"
    echo "LC_ALL=C.UTF-8"
}
mounts() {
    echo "\$0 /etc/rc bind,noexec"
    echo "${PWD} /deepops"
    echo "${HOME} ${HOME}"
}
if [ "\$0" = "/etc/rc" ]; then
    cd /deepops

    if [ ! -f .setup_done ] ; then
        echo "Setting up for first use..."
        echo "Downloading Ansible Galaxy roles..." && ansible-galaxy install -r requirements.yml >/dev/null 2>&1

        echo "Updating submodules..." && git submodule update --init

        # Copy default configuration
        CONFIG_DIR=\${CONFIG_DIR:-./config}
        if [ ! -d "\${CONFIG_DIR}" ] ; then
            cp -rfp ./config.example "\${CONFIG_DIR}"
            echo "Copied default configuration to \${CONFIG_DIR}"
        else
            echo "Configuration directory '\${CONFIG_DIR}' exists, not overwriting"
        fi

        touch .setup_done
    fi

    PROMPT_COMMAND='PS1="[deepops] \[\e]0;\u@\h: \w\a\]${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ ";unset PROMPT_COMMAND' bash
fi
EOF

./containers/setup/deepops.run --conf ${config}

rm -rf ${config}
