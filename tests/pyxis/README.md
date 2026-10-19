# Pyxis user namespace opt-out regression

Run from the repository root on Linux with Python 3, PyYAML,
`ansible-playbook`, the `ansible.posix` collection, procps `sysctl`,
`systemd-sysctl` and rootless `bwrap` available:

```sh
python3 tests/pyxis/test_userns_optout.py --scratch /path/to/fresh-test-directory
```

The directory must not exist yet. The script saves per-invocation Ansible logs
and prints a JSON summary on success. A nonzero exit is a failing regression,
not an expected defect reproduction. To check the negative control, pass
`--source /path/to/checkout-without-the-fix`; the test must fail with
`Opt-out left runtime permissive`.

The fixture runs the role's actual kernel probe, opt-in task and opt-out tasks
with real Ansible modules. Bubblewrap makes the host root read-only, disables
networking, and replaces `/proc/sys` and sysctl configuration directories with
fixture files. Both procps and systemd operate on those ordinary files, not the
host kernel. Error injection substitutes only the replay executable or denies
access to the fixture knob. No privilege escalation is used. If rootless
namespaces are unavailable, the test fails rather than falling back to a host
run. Use a host with merged `/usr` or the usual `/usr/lib/systemd` and
`/lib/systemd` paths available.

Coverage includes opt-in, opt-out, idempotence, retries after partial cleanup,
remaining permissive policy, absent policy, exact preservation of unrelated
entries (including duplicate keys), node/kernel guards, check mode, missing
replay executable, read/replay errors, and real systemd symlink/mask/glob
resolution. Unrelated runtime keys must stay unchanged.

The test does not run package installation, AppArmor profile loading, or Slurm,
and ordinary files cannot reproduce every kernel error. It is offline
role-boundary regression coverage, not live-host certification.
