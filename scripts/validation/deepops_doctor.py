#!/usr/bin/env python3
"""Preflight checks for a DeepOps provisioning environment.

Run this from the DeepOps repository root on the provisioning machine before
running cluster playbooks. It verifies the local environment (Ansible, Galaxy
dependencies, Kubespray submodule, configuration directory, inventory, and
whether the inventory's group layout matches what the Slurm and Kubernetes
cluster playbooks expect) and, with ``--remote``, host reachability and GPU
visibility over the configured inventory.

The default output is one line per check. With ``--json`` the script prints a
single JSON object with a stable ``checks`` list so automation and AI agents
can consume the result directly.

Exit codes: 0 = all checks passed, 1 = one or more checks failed,
2 = not run from a DeepOps repository root.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys


def run(cmd, timeout=120, env=None):
    """Run a command, returning (rc, stdout, stderr) without raising."""
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, env=env
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout after %ss" % timeout
    except FileNotFoundError:
        return 127, "", "command not found: %s" % cmd[0]


def check(checks, name, ok, detail):
    checks.append({"name": name, "ok": bool(ok), "detail": detail})
    return ok


def count_positive_stdout_hosts(output):
    """Count hosts whose ansible one-line ``(stdout) N`` value is a positive int."""
    hosts = 0
    for line in output.splitlines():
        if "(stdout)" not in line:
            continue
        tail = line.rsplit("(stdout)", 1)[1].strip()
        first = tail.split("\\n")[0].strip()
        try:
            if int(first) > 0:
                hosts += 1
        except ValueError:
            continue
    return hosts


def count_inventory_hosts(inventory_json):
    """Count hosts and detect DeepOps groups in ``ansible-inventory --list`` output."""
    hosts = set()
    meta = inventory_json.get("_meta", {}).get("hostvars", {})
    hosts.update(meta.keys())
    for group, data in inventory_json.items():
        if group == "_meta" or not isinstance(data, dict):
            continue
        hosts.update(data.get("hosts", []))
    groups = [g for g in inventory_json if g not in ("_meta", "all", "ungrouped")]
    return len(hosts), sorted(groups)


# Groups the two top-level cluster playbooks are built around. The umbrella
# groups are what the golden-path ``--limit`` arguments name.
SLURM_CORE_GROUPS = ("slurm-master", "slurm-node")
SLURM_UMBRELLA_GROUP = "slurm-cluster"
K8S_CORE_GROUPS = ("kube_control_plane", "etcd", "kube_node")
K8S_UMBRELLA_GROUP = "k8s_cluster"

# Spellings that look like a DeepOps/Kubespray group but are not one. The
# playbooks silently skip hosts in these, so the inventory "parses" and the
# deploy does nothing useful.
GROUP_NAME_ALIASES = {
    "slurm_master": "slurm-master",
    "slurm_node": "slurm-node",
    "slurm_login": "slurm-login",
    "slurm_nfs": "slurm-nfs",
    "slurm_cache": "slurm-cache",
    "slurm_metric": "slurm-metric",
    "slurm_cluster": "slurm-cluster",
    "kube-master": "kube_control_plane",
    "kube_master": "kube_control_plane",
    "kube-control-plane": "kube_control_plane",
    "kube-node": "kube_node",
    "k8s-cluster": "k8s_cluster",
}


def resolve_group_hosts(inventory_json, group, _seen=None):
    """Return the set of hosts in ``group``, following ``children`` recursively."""
    _seen = _seen if _seen is not None else set()
    if group in _seen:
        return set()
    _seen.add(group)
    data = inventory_json.get(group)
    if not isinstance(data, dict):
        return set()
    hosts = set(data.get("hosts", []))
    for child in data.get("children", []):
        hosts |= resolve_group_hosts(inventory_json, child, _seen)
    return hosts


def check_inventory_topology(inventory_json):
    """Compare the inventory's group layout with what the cluster playbooks expect.

    Returns ``(ok, detail)``. ``ok`` is False when the layout would make
    ``slurm-cluster.yml`` or ``k8s-cluster.yml`` skip hosts or fail: a core
    group is missing while its siblings are populated, the umbrella group used
    with ``--limit`` does not cover the core groups, a group name is a
    near-miss of a real one, or no cluster groups are defined at all. Hosts in
    no cluster group and hosts in both Slurm and Kubernetes groups are reported
    in the detail but do not fail the check.
    """
    all_hosts, _ = count_inventory_hosts(inventory_json)
    groups = {
        g: resolve_group_hosts(inventory_json, g)
        for g in inventory_json
        if g not in ("_meta", "all", "ungrouped")
    }
    problems = []
    notes = []

    for alias, real in sorted(GROUP_NAME_ALIASES.items()):
        if alias in groups and groups[alias] and real not in groups:
            problems.append(
                "group '%s' looks like a misspelling of '%s' (playbooks will skip it)"
                % (alias, real)
            )

    slurm_hosts = {g: groups.get(g, set()) for g in SLURM_CORE_GROUPS}
    slurm_any = set().union(*slurm_hosts.values())
    if slurm_any:
        for g, hosts in slurm_hosts.items():
            if not hosts:
                problems.append("Slurm group '%s' is empty" % g)
        umbrella = groups.get(SLURM_UMBRELLA_GROUP, set())
        uncovered = slurm_any - umbrella
        if uncovered:
            problems.append(
                "%d Slurm host(s) not in '%s' (-l %s skips them): %s"
                % (len(uncovered), SLURM_UMBRELLA_GROUP, SLURM_UMBRELLA_GROUP,
                   ", ".join(sorted(uncovered)))
            )

    k8s_hosts = {g: groups.get(g, set()) for g in K8S_CORE_GROUPS}
    k8s_any = set().union(*k8s_hosts.values())
    if k8s_any:
        for g, hosts in k8s_hosts.items():
            if not hosts:
                problems.append("Kubernetes group '%s' is empty" % g)
        umbrella = groups.get(K8S_UMBRELLA_GROUP, set())
        uncovered = (k8s_hosts["kube_control_plane"] | k8s_hosts["kube_node"]) - umbrella
        if uncovered:
            problems.append(
                "%d Kubernetes host(s) not in '%s' (-l %s skips them): %s"
                % (len(uncovered), K8S_UMBRELLA_GROUP, K8S_UMBRELLA_GROUP,
                   ", ".join(sorted(uncovered)))
            )

    if all_hosts and not slurm_any and not k8s_any:
        problems.append(
            "no hosts in %s or %s; the cluster playbooks will not touch any host"
            % ("/".join(SLURM_CORE_GROUPS), "/".join(K8S_CORE_GROUPS))
        )

    hosts_in_some_group = set().union(*groups.values()) if groups else set()
    meta_hosts = set(inventory_json.get("_meta", {}).get("hostvars", {}))
    ungrouped = set(inventory_json.get("ungrouped", {}).get("hosts", []))
    stray = (meta_hosts | ungrouped) - slurm_any - k8s_any
    stray |= hosts_in_some_group - slurm_any - k8s_any
    if stray and (slurm_any or k8s_any):
        notes.append(
            "%d host(s) in no cluster group: %s" % (len(stray), ", ".join(sorted(stray)))
        )

    mixed = slurm_hosts["slurm-node"] & k8s_hosts["kube_node"]
    if mixed:
        notes.append(
            "%d host(s) in both slurm-node and kube_node: %s"
            % (len(mixed), ", ".join(sorted(mixed)))
        )

    summary = "slurm: %d master, %d node; kubernetes: %d control-plane, %d etcd, %d node" % (
        len(slurm_hosts["slurm-master"]),
        len(slurm_hosts["slurm-node"]),
        len(k8s_hosts["kube_control_plane"]),
        len(k8s_hosts["etcd"]),
        len(k8s_hosts["kube_node"]),
    )
    detail = "; ".join([summary] + problems + notes)
    return not problems, detail


def main():
    parser = argparse.ArgumentParser(
        description="Preflight checks for a DeepOps provisioning environment."
    )
    parser.add_argument("--json", action="store_true", help="emit one JSON object")
    parser.add_argument(
        "--inventory",
        default="",
        help="inventory path (default: config/inventory via ansible.cfg)",
    )
    parser.add_argument(
        "--remote",
        action="store_true",
        help="also check host reachability and GPU visibility over SSH",
    )
    args = parser.parse_args()

    root = os.getcwd()
    if not os.path.exists(os.path.join(root, "ansible.cfg")) or not os.path.isdir(
        os.path.join(root, "playbooks")
    ):
        print(
            "error: run from the DeepOps repository root (ansible.cfg not found)",
            file=sys.stderr,
        )
        return 2

    checks = []

    rc, out, _ = run(["ansible", "--version"], timeout=60)
    ansible_ok = check(
        checks,
        "ansible_installed",
        rc == 0,
        out.splitlines()[0] if rc == 0 and out else "install Ansible via ./scripts/setup.sh",
    )
    check(
        checks,
        "ansible_playbook_installed",
        shutil.which("ansible-playbook") is not None,
        "ansible-playbook on PATH" if shutil.which("ansible-playbook") else "missing ansible-playbook",
    )

    galaxy_marker = os.path.join(root, "roles", "galaxy")
    check(
        checks,
        "galaxy_dependencies_installed",
        os.path.isdir(galaxy_marker) and bool(os.listdir(galaxy_marker)),
        "roles/galaxy populated"
        if os.path.isdir(galaxy_marker) and os.listdir(galaxy_marker)
        else "run ./scripts/setup.sh to install Ansible Galaxy requirements",
    )

    kubespray_marker = os.path.join(root, "submodules", "kubespray", "cluster.yml")
    check(
        checks,
        "kubespray_submodule_initialized",
        os.path.exists(kubespray_marker),
        "submodules/kubespray present"
        if os.path.exists(kubespray_marker)
        else "run: git submodule update --init --recursive",
    )

    config_dir = os.environ.get("DEEPOPS_CONFIG_DIR", os.path.join(root, "config"))
    config_ok = check(
        checks,
        "config_dir_exists",
        os.path.isdir(config_dir),
        config_dir
        if os.path.isdir(config_dir)
        else "copy config.example/ to config/ and edit the inventory",
    )

    inventory = args.inventory or os.path.join(config_dir, "inventory")
    hosts_total = 0
    groups = []
    if ansible_ok and config_ok and os.path.exists(inventory):
        rc, out, err = run(
            ["ansible-inventory", "-i", inventory, "--list"], timeout=120
        )
        parsed_ok = False
        inventory_json = {}
        if rc == 0:
            try:
                inventory_json = json.loads(out)
                hosts_total, groups = count_inventory_hosts(inventory_json)
                parsed_ok = True
            except json.JSONDecodeError:
                # Leave parsed_ok False; the inventory_parses check below
                # reports the failure with the ansible-inventory context.
                parsed_ok = False
        check(
            checks,
            "inventory_parses",
            parsed_ok,
            "%d host(s), groups: %s" % (hosts_total, ", ".join(groups))
            if parsed_ok
            else "ansible-inventory failed: %s" % (err or "unparseable output"),
        )
        if parsed_ok:
            check(
                checks,
                "inventory_has_hosts",
                hosts_total > 0,
                "%d host(s) defined" % hosts_total
                if hosts_total
                else "inventory defines no hosts",
            )
        if parsed_ok and hosts_total > 0:
            topology_ok, topology_detail = check_inventory_topology(inventory_json)
            check(checks, "inventory_topology", topology_ok, topology_detail)
    else:
        check(
            checks,
            "inventory_parses",
            False,
            "inventory not found at %s" % inventory,
        )

    if args.remote and hosts_total > 0:
        rc, out, err = run(
            ["ansible", "all", "-i", inventory, "-m", "ping", "-o"], timeout=300
        )
        reachable = out.count("SUCCESS")
        check(
            checks,
            "hosts_reachable",
            rc == 0,
            "%d/%d host(s) reachable" % (reachable, hosts_total),
        )

        rc, out, _ = run(
            [
                "ansible", "all", "-i", inventory, "-m", "shell", "-o",
                "-a", "lspci 2>/dev/null | grep -ci nvidia || true",
            ],
            timeout=300,
        )
        gpu_hosts = count_positive_stdout_hosts(out) if rc == 0 else 0
        check(
            checks,
            "gpus_detected_on_hosts",
            True,
            "%d host(s) report NVIDIA PCI devices (informational)" % gpu_hosts,
        )

        rc, out, _ = run(
            [
                "ansible", "all", "-i", inventory, "-m", "shell", "-o",
                "-a", "systemctl show ssh.service sshd.service -p DeviceAllow 2>/dev/null | grep -ci nvidiactl || true",
            ],
            timeout=300,
        )
        overrides = count_positive_stdout_hosts(out) if rc == 0 else 0
        check(
            checks,
            "ssh_gpu_visibility_override",
            True,
            "%d host(s) restrict GPU device access for SSH sessions (Slurm login "
            "GPU hiding); on those hosts direct nvidia-smi over SSH is expected to "
            "fail and srun is the authoritative GPU test" % overrides,
        )

    ok = all(c["ok"] for c in checks)
    result = {"ok": ok, "checks": checks}

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        for c in checks:
            print("%s %s: %s" % ("PASS" if c["ok"] else "FAIL", c["name"], c["detail"]))
        print("ok=%s" % ok)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
