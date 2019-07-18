
    test -f requirements.yml && ansible-galaxy install -r requirements.yml

    git submodule status && git submodule update --init

    # Copy default configuration
    CONFIG_DIR=${CONFIG_DIR:-./config}
    if [ ! -d "${CONFIG_DIR}" ] ; then
        test -d config.example && cp -rfp ./config.example "${CONFIG_DIR}"
    else
        echo "Configuration directory '${CONFIG_DIR}' exists, not overwriting"
    fi

