import os
from configparser import ConfigParser


def config_file_path():
    """Get the path for the DeepOps CLI config file"""
    if os.environ.get("DEEPOPS_CONFIG_FILE"):
        return os.environ.get("DEEPOPS_CONFIG_FILE")
    if os.environ.get("XDG_CONFIG_HOME"):
        return "{}/deepops.cfg".format(os.environ.get("XDG_CONFIG_HOME"))
    if os.environ.get("HOME"):
        return "{}/.config/deepops.cfg".format(os.environ.get("HOME"))
    else:
        raise Exception("No DEEPOPS_CONFIG_FILE and default locations cannot be found")


def get_config(config_path=None):
    """Load configuration for DeepOps CLI"""
    if not config_path:
        config_path = config_file_path()
    config = ConfigParser()
    config.read(config_path)
    return config
