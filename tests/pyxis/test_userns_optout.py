#!/usr/bin/env python3
"""Offline role regression using real Ansible, sysctl and systemd-sysctl.

Requires ansible-playbook, ansible.posix, PyYAML and rootless bubblewrap.
The host root is read-only; /proc/sys and sysctl configuration are replaced by
ordinary fixture files inside a private namespace. No sudo, network or live
kernel writes. Only the role's knob probe and sysctl tasks execute, not package,
AppArmor profile, or Slurm installation tasks. This is not live-kernel QA.

Run with --scratch <fresh-directory>. --source <checkout> tests another revision.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

import yaml

KEY = "kernel.apparmor_restrict_unprivileged_userns"
DROPIN = "60-enroot-userns.conf"
UNRELATED = "  # administrator comment  \nvm.swappiness = 20\nvm.swappiness = 30\n\n"


class Fixture:
    def __init__(self, scratch, source):
        self.scratch = scratch.resolve()
        self.source = source.resolve()
        self.results = []
        main = yaml.safe_load((self.source / "roles/pyxis/tasks/main.yml").read_text())
        self.tasks = []
        for task in main:
            if (task.get("stat", {}).get("path") == "/proc/sys/" + KEY.replace(".", "/")
                    or task.get("ansible.posix.sysctl", {}).get("name") == KEY):
                self.tasks.append(task)
            elif task.get("include_tasks") == "userns-optout.yml":
                task["include_tasks"] = str(self.source / "roles/pyxis/tasks/userns-optout.yml")
                self.tasks.append(task)
        assert self.tasks, "No production tasks selected"

    def case(self, name, runtime="0", dropin=KEY + "=0\n", policy="1"):
        case = self.scratch / name
        case.mkdir(parents=True)
        for directory in ("etc", "vendor", "empty", "proc/kernel", "proc/vm", "local", "remote", "home"):
            (case / directory).mkdir(parents=True)
        if runtime is not None:
            (case / "proc/kernel/apparmor_restrict_unprivileged_userns").write_text(runtime + "\n")
        (case / "proc/vm/swappiness").write_text("60\n")
        if dropin is not None:
            (case / "etc" / DROPIN).write_text(dropin)
        if policy is not None:
            (case / "vendor/10-default.conf").write_text(KEY + "=" + policy + "\n")
        (case / "empty.conf").write_text("")
        (case / "ansible.cfg").write_text("[defaults]\nretry_files_enabled=False\nhost_key_checking=True\n")
        return case

    def runtime(self, case):
        p = case / "proc/kernel/apparmor_restrict_unprivileged_userns"
        return p.read_text().strip() if p.exists() else None

    def snapshot(self, case):
        return {str(p.relative_to(case)): p.read_bytes()
                for directory in ("etc", "proc", "vendor")
                for p in (case / directory).rglob("*") if p.is_file()}

    def run(self, case, *, enabled=False, compute=True, check=False,
            missing_binary=False, replay_error=False, read_error=False, expect_failure=None):
        play = [{"hosts": "localhost", "connection": "local", "gather_facts": False,
                 "become": False,
                 "vars": {"ansible_python_interpreter": shutil.which("python3"),
                          "is_compute": compute, "pyxis_userns_allow_globally": enabled},
                 "tasks": self.tasks}]
        path = case / "play.yml"
        path.write_text(yaml.safe_dump(play, sort_keys=False))
        # Both sysctl implementations operate on fake /proc/sys, not the host.
        cmd = ["bwrap", "--unshare-all", "--die-with-parent", "--ro-bind", "/", "/",
               "--dev", "/dev", "--bind", str(case), str(case),
               "--bind", str(case / "etc"), "/etc/sysctl.d",
               "--ro-bind", str(case / "vendor"), "/usr/lib/sysctl.d",
               "--ro-bind", str(case / "empty.conf"), "/etc/sysctl.conf",
               "--tmpfs", "/run", "--dir", "/run/sysctl.d",
               "--bind", str(case / "proc"), "/proc/sys"]
        # Some distributions still read these additional policy directories.
        for directory in ("/lib/sysctl.d", "/usr/local/lib/sysctl.d"):
            if Path(directory).is_dir():
                fixture = "vendor" if directory == "/lib/sysctl.d" else "empty"
                cmd += ["--ro-bind", str(case / fixture), directory]
        if missing_binary:
            cmd += ["--tmpfs", "/usr/lib/systemd", "--tmpfs", "/lib/systemd"]
        if replay_error:
            stub = case / "replay-error"
            stub.write_text("#!/bin/sh\necho 'injected replay error' >&2\nexit 42\n")
            stub.chmod(0o700)
            cmd += ["--ro-bind", str(stub), "/usr/lib/systemd/systemd-sysctl",
                    "--ro-bind", str(stub), "/lib/systemd/systemd-sysctl"]
        if read_error:
            # The actual command is called but cannot open the simulated knob.
            (case / "proc/kernel/apparmor_restrict_unprivileged_userns").chmod(0)
        cmd += [shutil.which("ansible-playbook"), "-i", "localhost,", str(path)]
        if check:
            cmd += ["--check"]
        env = dict(os.environ, ANSIBLE_CONFIG=str(case / "ansible.cfg"),
                   ANSIBLE_LOCAL_TEMP=str(case / "local"), ANSIBLE_REMOTE_TEMP=str(case / "remote"),
                   ANSIBLE_HOME=str(case / "home"), ANSIBLE_NOCOLOR="1",
                   ANSIBLE_COLLECTIONS_PATH=os.environ.get(
                       "ANSIBLE_COLLECTIONS_PATH",
                       str(Path.home() / ".ansible/collections") + ":/usr/share/ansible/collections"))
        result = subprocess.run(cmd, env=env, cwd=case, text=True, capture_output=True, timeout=90)
        if read_error:
            (case / "proc/kernel/apparmor_restrict_unprivileged_userns").chmod(0o600)
        output = result.stdout + result.stderr
        log = case / ("run-%02d.log" % len(list(case.glob("run-*.log"))))
        log.write_text(output)
        if expect_failure:
            assert result.returncode != 0 and expect_failure in output, output
        else:
            assert result.returncode == 0, output
        recap = re.search(r"localhost\s+: ok=\d+\s+changed=(\d+).*failed=(\d+)", output)
        assert recap, output
        self.results.append({"case": case.name, "enabled": enabled, "check": check,
                             "exit": result.returncode, "changed": int(recap[1]),
                             "expected_failure": expect_failure})
        return int(recap[1])

    def test(self):
        # Missing cleanup must fail here against the original role.
        c = self.case("opt-in-out", runtime="1", dropin=None)
        self.run(c, enabled=True)
        assert self.runtime(c) == "0", "Opt-in did not enable user namespaces"
        assert (c / "etc" / DROPIN).read_text() == KEY + "=0\n"
        assert self.run(c, enabled=True) == 0, "Opt-in rerun was not idempotent"
        self.run(c)
        assert self.runtime(c) == "1", "Opt-out left runtime permissive"
        assert not (c / "etc" / DROPIN).exists(), "Empty role drop-in was not removed"
        assert self.run(c) == 0, "Rerun was not idempotent"

        # Cleanup must preserve bytes/duplicate administrator entries and not reload them.
        c = self.case("unrelated", dropin=UNRELATED + KEY + "=0\n")
        self.run(c)
        assert (c / "etc" / DROPIN).read_bytes() == UNRELATED.encode()
        assert (c / "proc/vm/swappiness").read_text() == "60\n"
        assert self.runtime(c) == "1"

        for name, policy in (("admin-permissive", "0"), ("no-declaration", None)):
            c = self.case(name, policy=policy)
            self.run(c, expect_failure="administrator")
            assert self.runtime(c) == "0", "Opt-out forced a restrictive value"
            assert not (c / "etc" / DROPIN).exists()
            self.run(c, expect_failure="administrator")

        # Replay is unconditional even if a previous run already removed the entry.
        c = self.case("interrupted", dropin=None)
        assert self.run(c) == 1
        assert self.runtime(c) == "1"
        assert self.run(c) == 0

        for name, kwargs in (("controller", {"compute": False}),
                             ("no-knob", {}), ("check", {"check": True})):
            c = self.case(name, runtime=None if name == "no-knob" else "0")
            before = self.snapshot(c)
            changed = self.run(c, **kwargs)
            assert self.snapshot(c) == before, name + " changed host state"
            assert changed == (1 if name == "check" else 0)

        c = self.case("check-unrelated", dropin=UNRELATED + KEY + "=0\n")
        before = self.snapshot(c)
        assert self.run(c, check=True) == 1
        assert self.snapshot(c) == before

        c = self.case("missing-binary")
        self.run(c, missing_binary=True, expect_failure="systemd-sysctl")
        assert self.runtime(c) == "0"
        c = self.case("read-error")
        self.run(c, read_error=True, expect_failure="read the user namespace restriction before replay")
        assert "TASK [reapply only" not in (c / "run-00.log").read_text()
        assert self.runtime(c) == "0"
        c = self.case("replay-error")
        self.run(c, replay_error=True, expect_failure="injected replay error")
        assert self.runtime(c) == "0"
        self.run(c)
        assert self.runtime(c) == "1", "Retry after replay failure did not converge"

        # Real systemd policy resolution: masked vendor file, symlink and glob.
        c = self.case("systemd-policy", policy="0")
        (c / "etc/10-default.conf").symlink_to("/dev/null")
        (c / "site.conf").write_text("kernel.apparmor_restrict_unprivileged_usern?=1\nvm.swappiness=5\n")
        (c / "etc/90-site.conf").symlink_to(c / "site.conf")
        self.run(c)
        assert self.runtime(c) == "1"
        assert (c / "proc/vm/swappiness").read_text() == "60\n", "Replayed an unrelated key"
        print(json.dumps({"passed": True, "invocations": len(self.results), "results": self.results}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch", required=True, type=Path)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    if args.scratch.exists():
        raise SystemExit("Use a fresh --scratch directory")
    for tool in ("bwrap", "ansible-playbook", "python3"):
        if not shutil.which(tool):
            raise SystemExit("Required tool is missing: " + tool)
    Fixture(args.scratch, args.source).test()


if __name__ == "__main__":
    main()
