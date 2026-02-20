#!/usr/bin/env python3
"""MAAS Dynamic Inventory Script for Ansible.

Queries a Canonical MAAS server's REST API and generates Ansible inventory
based on machine tags. Machines tagged with Ansible group names (e.g.,
"slurm-master", "kube_node") are placed into those groups automatically.

Only machines in the "Deployed" state (status=6) are included.

Configuration is loaded from environment variables or a YAML config file.

Environment variables:
    MAAS_API_URL       MAAS API endpoint (e.g., http://maas-server:5240/MAAS/api/2.0)
    MAAS_API_KEY       OAuth1 key in consumer_key:token_key:token_secret format
    MAAS_SSH_USER      Default SSH user for all hosts (default: ubuntu)
    MAAS_NETWORK       Preferred network prefix for ansible_host IP (optional)
    MAAS_SSH_BASTION   SSH bastion for ProxyJump (optional, for private networks)

Config file (checked in order):
    1. Path in MAAS_INVENTORY_CONFIG env var
    2. config/maas-inventory.yml (repo-relative, created by setup.sh)
    3. ~/.config/maas-inventory.yml

Usage:
    ./scripts/maas_inventory.py --list
    ./scripts/maas_inventory.py --host <hostname>
    ansible-playbook -i scripts/maas_inventory.py playbooks/slurm-cluster.yml
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
import uuid
from pathlib import Path

# DeepOps group hierarchy: parent -> list of child groups.
# Tags in MAAS should match "leaf" group names. Preferred K8s tags use
# underscores (kube_control_plane, kube_node); old hyphenated tags
# (kube-master, kube-node) are accepted via TAG_ALIASES below.
# Slurm groups retain hyphens (slurm-master, slurm-node).
GROUP_CHILDREN = {
    "k8s_cluster": ["kube_control_plane", "kube_node"],
    "slurm-cluster": [
        "slurm-master", "slurm-node", "slurm-cache",
        "slurm-nfs", "slurm-metric", "slurm-login",
    ],
    "slurm-cache": ["slurm-master"],
    "slurm-nfs-client": ["slurm-node"],
    "slurm-metric": ["slurm-master"],
    "slurm-login": ["slurm-master"],
}

# Backward-compatible tag aliases: old MAAS tag name -> canonical group name.
# Users can tag machines with either the old or new name.
TAG_ALIASES = {
    "kube-master": "kube_control_plane",
    "kube-node": "kube_node",
    "k8s-cluster": "k8s_cluster",
}


def build_oauth1_header(api_key):
    """Build OAuth1 Authorization header for MAAS API."""
    parts = api_key.split(":")
    if len(parts) != 3:
        raise ValueError(
            "MAAS_API_KEY must be in format consumer_key:token_key:token_secret"
        )
    consumer_key, token_key, token_secret = parts
    return (
        f'OAuth oauth_version="1.0", '
        f'oauth_signature_method="PLAINTEXT", '
        f'oauth_consumer_key="{consumer_key}", '
        f'oauth_token="{token_key}", '
        f'oauth_signature="&{token_secret}", '
        f'oauth_nonce="{uuid.uuid4().hex}", '
        f'oauth_timestamp="{int(time.time())}"'
    )


def load_config():
    """Load configuration from env vars and/or YAML config file."""
    config = {
        "api_url": os.environ.get("MAAS_API_URL", ""),
        "api_key": os.environ.get("MAAS_API_KEY", ""),
        "ssh_bastion": os.environ.get("MAAS_SSH_BASTION", ""),
        "ssh_user": os.environ.get("MAAS_SSH_USER", ""),
        "network": os.environ.get("MAAS_NETWORK", ""),
    }

    # Try YAML config file if env vars are incomplete
    if not (config["api_url"] and config["api_key"]):
        config_paths = []
        if os.environ.get("MAAS_INVENTORY_CONFIG"):
            config_paths.append(Path(os.environ["MAAS_INVENTORY_CONFIG"]))
        # Repo-relative: config/maas-inventory.yml (created by setup.sh)
        repo_root = Path(__file__).parent.parent
        config_paths.append(repo_root / "config" / "maas-inventory.yml")
        config_paths.append(Path.home() / ".config" / "maas-inventory.yml")

        for path in config_paths:
            if path.exists():
                try:
                    import yaml
                    with open(path) as f:
                        file_config = yaml.safe_load(f) or {}
                    for key in config:
                        if not config[key] and key in file_config:
                            config[key] = str(file_config[key])
                    break
                except ImportError:
                    # PyYAML not available; try simple key: value parsing
                    with open(path) as f:
                        for line in f:
                            line = line.strip()
                            if line.startswith("#") or ":" not in line:
                                continue
                            k, v = line.split(":", 1)
                            k, v = k.strip(), v.strip().strip('"').strip("'")
                            if k in config and not config[k]:
                                config[k] = v
                    break

    # Detect unconfigured: empty values or placeholder templates from config.example
    api_url = config["api_url"]
    api_key = config["api_key"]
    if (not api_url or not api_key
            or "<" in api_url or "<" in api_key
            or api_key == "CONSUMER_KEY:TOKEN_KEY:TOKEN_SECRET"):
        # Return gracefully so ansible doesn't fail when MAAS isn't configured.
        # This allows the dynamic inventory to coexist with static inventory
        # in ansible.cfg without errors for users who don't use MAAS.
        config["_unconfigured"] = True
        return config

    # Defaults
    if not config["ssh_user"]:
        config["ssh_user"] = "ubuntu"

    return config


def maas_api_get(url, api_key):
    """Make an authenticated GET request to the MAAS API."""
    auth_header = build_oauth1_header(api_key)
    req = urllib.request.Request(url)
    req.add_header("Authorization", auth_header)
    req.add_header("Accept", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as e:
        print(f"MAAS API error: {e.code} {e.reason}", file=sys.stderr)
        if e.code == 401:
            print("Check your MAAS_API_KEY value.", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"MAAS connection error: {e.reason}", file=sys.stderr)
        print("Check MAAS_API_URL and network connectivity.", file=sys.stderr)
        sys.exit(1)


def get_preferred_ip(machine, network_filter):
    """Select the best IP for a machine, preferring the filtered network."""
    ips = machine.get("ip_addresses", [])
    if not ips:
        return ""
    if network_filter:
        for ip in ips:
            if ip.startswith(network_filter):
                return ip
    return ips[0]


def build_inventory(config):
    """Query MAAS API and build Ansible inventory."""
    api_url = config["api_url"].rstrip("/")
    machines_url = f"{api_url}/machines/"

    machines = maas_api_get(machines_url, config["api_key"])

    inventory = {
        "_meta": {"hostvars": {}},
        "all": {"hosts": [], "vars": {}},
    }

    # Pre-create parent groups with children relationships
    for parent, children in GROUP_CHILDREN.items():
        inventory[parent] = {"children": children, "hosts": []}

    for machine in machines:
        # Only include Deployed machines
        if machine.get("status") != 6:
            continue

        hostname = machine.get("hostname", "")
        if not hostname:
            continue

        ip = get_preferred_ip(machine, config.get("network", ""))
        tags = machine.get("tag_names", [])

        # Build hostvars
        hostvars = {
            "ansible_python_interpreter": "/usr/bin/python3",
        }
        if ip:
            hostvars["ansible_host"] = ip
        if config.get("ssh_user"):
            hostvars["ansible_user"] = config["ssh_user"]
        if config.get("ssh_bastion"):
            hostvars["ansible_ssh_common_args"] = (
                f'-o ProxyJump="{config["ssh_bastion"]}"'
            )

        # MAAS metadata
        hostvars["maas_system_id"] = machine.get("system_id", "")
        hostvars["maas_fqdn"] = machine.get("fqdn", "")
        hostvars["maas_status"] = machine.get("status_name", "")
        hostvars["maas_zone"] = machine.get("zone", {}).get("name", "")
        hostvars["maas_pool"] = machine.get("pool", {}).get("name", "")
        hostvars["maas_tags"] = tags
        hostvars["maas_arch"] = machine.get("architecture", "")
        hostvars["maas_os"] = machine.get("osystem", "")
        hostvars["maas_distro"] = machine.get("distro_series", "")
        hostvars["maas_cpus"] = machine.get("cpu_count", 0)
        hostvars["maas_memory_mb"] = machine.get("memory", 0)
        hostvars["maas_power_state"] = machine.get("power_state", "")

        inventory["_meta"]["hostvars"][hostname] = hostvars
        inventory["all"]["hosts"].append(hostname)

        # Map tags to Ansible groups (apply aliases for renamed K8s groups)
        for tag in tags:
            group = TAG_ALIASES.get(tag, tag)
            if group not in inventory:
                inventory[group] = {"hosts": [], "vars": {}}
            elif "hosts" not in inventory[group]:
                inventory[group]["hosts"] = []
            inventory[group]["hosts"].append(hostname)

    return inventory


def main():
    parser = argparse.ArgumentParser(
        description="MAAS Dynamic Inventory for DeepOps"
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--list", action="store_true", help="List all hosts")
    group.add_argument("--host", help="Get variables for a specific host")
    args = parser.parse_args()

    config = load_config()

    # If MAAS is not configured, return empty inventory (no error)
    if config.get("_unconfigured"):
        if args.list:
            print(json.dumps({"_meta": {"hostvars": {}}}))
        else:
            print(json.dumps({}))
        return

    if args.list:
        inventory = build_inventory(config)
        print(json.dumps(inventory, indent=2))
    elif args.host:
        # Ansible uses hostvars from _meta in --list and typically does
        # not call --host when _meta is provided. Return empty dict to
        # avoid an unnecessary MAAS API call.
        print(json.dumps({}))


if __name__ == "__main__":
    main()
