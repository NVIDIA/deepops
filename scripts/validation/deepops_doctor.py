#!/usr/bin/env python3
"""Preflight checks for a DeepOps provisioning environment.

Run this from the DeepOps repository root on the provisioning machine before
running cluster playbooks. It verifies the local environment (Ansible, Galaxy
dependencies, Kubespray submodule, configuration directory, inventory) and,
with ``--remote``, host reachability and GPU visibility over the configured
inventory.

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
        if rc == 0:
            try:
                hosts_total, groups = count_inventory_hosts(json.loads(out))
                parsed_ok = True
            except json.JSONDecodeError:
                pass
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
                "-a", "ls /etc/systemd/system/ssh.service.d /etc/systemd/system/sshd.service.d 2>/dev/null | wc -l",
            ],
            timeout=300,
        )
        overrides = count_positive_stdout_hosts(out) if rc == 0 else 0
        check(
            checks,
            "ssh_gpu_visibility_override",
            True,
            "%d host(s) have sshd systemd overrides; on Slurm nodes GPUs are hidden "
            "outside srun jobs and direct nvidia-smi over SSH is expected to fail"
            % overrides,
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
