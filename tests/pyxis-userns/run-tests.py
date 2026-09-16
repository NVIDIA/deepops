#!/usr/bin/env python3
"""Evaluate the ``when:`` conditions of named tasks in roles/pyxis/tasks/main.yml.

The sysctl reconciliation in that role is a chain of guards, and the faults it
has carried were never syntax -- they were a guard that let a task run in a
state it had no business running in. Those states need a host in a particular
condition to reach, which CI does not have, so the conditions themselves are
put under test instead.

This proves which tasks a given host state selects. It does not prove what the
selected tasks then do on a host; the module behaviour they rely on is noted in
the task comments and in the pull request.
"""
import base64
import sys

import yaml
from jinja2 import Environment, StrictUndefined


def load_tasks(path):
    with open(path) as handle:
        return yaml.safe_load(handle)


def find_task(tasks, name):
    for task in tasks:
        if isinstance(task, dict) and task.get("name") == name:
            return task
    raise KeyError("no task named %r" % name)


def make_env():
    env = Environment(undefined=StrictUndefined)
    # b64decode is an Ansible filter, not a Jinja one. slurp returns base64, so
    # every condition that reads /proc goes through it.
    env.filters["b64decode"] = lambda value: base64.b64decode(value).decode()
    return env


def selects(env, task, variables, drop=()):
    """True when every condition in the task's when: holds for these variables.

    ``drop`` removes conditions by substring before evaluating, which is how a
    scenario is replayed against the pre-fix form of a guard.
    """
    conditions = task.get("when", [])
    if isinstance(conditions, str):
        conditions = [conditions]
    for condition in conditions:
        if any(marker in condition for marker in drop):
            continue
        if not env.compile_expression(condition)(**variables):
            return False
    return True


def b64(value):
    return base64.b64encode(value.encode()).decode()


# Host states. Every one of them has the fallback off (the default), the kernel
# knob present, and the node in the compute group -- the path this role takes on
# a supported Ubuntu.
def state(effective, after=None, declared=""):
    variables = {
        "is_compute": True,
        "pyxis_userns_allow_globally": False,
        "apparmor_userns_knob": {"stat": {"exists": True}},
        "enroot_userns_effective": {"content": b64(effective)},
        "enroot_userns_declared_in": {
            "stdout": declared,
            "stdout_lines": declared.split() if declared else [],
        },
    }
    if after is not None:
        variables["enroot_userns_effective_after"] = {"content": b64(after)}
    else:
        # The re-read is itself skipped when the first read already said 1, so
        # the variable does not exist. default() in the conditions covers that;
        # leaving it out here is what keeps that cover honest.
        variables["enroot_userns_effective_after"] = {}
    return variables


SCENARIOS = {
    # An administrator file declares the key and holds it at 0. The replay
    # preserved their choice; writing 1 over it would undo a deliberate
    # decision, and would then make the final check pass.
    "admin declares 0": state("0\n", "0\n", "/etc/sysctl.d/91-enroot.conf"),
    # The fallback was on, the run was interrupted after the managed line was
    # removed, and nothing else declares the key. The value left in the kernel
    # is this role's own, so restoring it invents nothing.
    "interrupted removal": state("0\n", "0\n", ""),
    # The replay found another file that declares 1 and put it back.
    "replay restored it": state("0\n", "1\n", ""),
    # Nothing to do.
    "already restricted": state("1\n", None, ""),
}


EXPECTED = {
    # label: (write runs, final failure runs)
    "admin declares 0": (False, True),
    "interrupted removal": (True, False),
    "replay restored it": (False, False),
    "already restricted": (False, False),
}


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "roles/pyxis/tasks/main.yml"
    tasks = load_tasks(path)
    env = make_env()

    write = find_task(tasks, "undo the runtime value this role left behind")
    fail = find_task(tasks, "fail when the user namespace restriction could not be restored")
    removal = find_task(tasks, "drop the host-wide user namespace sysctl when the fallback is off")

    passed = failed = 0

    def check(label, actual, expected):
        nonlocal passed, failed
        if actual == expected:
            print("  ok   %s" % label)
            passed += 1
        else:
            print("  FAIL %s" % label)
            print("       expected %r, got %r" % (expected, actual))
            failed += 1

    print("pyxis userns sysctl reconciliation -- which tasks a host state selects")
    for label, variables in SCENARIOS.items():
        wrote = selects(env, write, variables)
        # The final failure reads /proc again. Model that read as the value the
        # kernel would hold once the write above has or has not happened.
        after = variables["enroot_userns_effective_after"].get("content")
        final = "1\n" if wrote else (base64.b64decode(after).decode() if after else "1\n")
        state_now = dict(variables, enroot_userns_final={"content": b64(final)})
        check(label, (wrote, selects(env, fail, state_now)), EXPECTED[label])

    print()
    print("the guard is what decides -- the same state without it")
    # Take the evidence condition back out and replay the administrator state.
    # Without this the suite could pass while proving nothing.
    mutant = selects(env, write, SCENARIOS["admin declares 0"],
                     drop=("enroot_userns_declared_in",))
    check("without the declaration check, the write overrides the administrator",
          mutant, True)

    print()
    print("removal task -- no whole-file reload")
    # ansible.posix.sysctl reloads by default, and with state=absent that runs
    # "sysctl -p" over the whole file, reapplying any other key an
    # administrator put there.
    check("the removal passes reload: false",
          removal["ansible.posix.sysctl"].get("reload"), False)

    print()
    print("%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
