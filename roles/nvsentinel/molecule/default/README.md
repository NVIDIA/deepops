# Offline NVSentinel role tests

Run `molecule test` from `roles/nvsentinel`. The scenario uses disposable Ubuntu
22.04 and 24.04 Docker containers, without privileged mode or a Kubernetes cluster.
Preparation installs Python virtual-environment support and pinned test dependencies;
convergence copies the real role and its offline test harness into each container.
Verification runs the role owner's test suite plus check-mode regressions against
strict kubectl/Helm fixtures. No workstation executable or kubeconfig is used.

The suite exercises missing reboot acknowledgement, remediation with dry-run,
zero GPU-labelled nodes, single-GPU-node fallback, full-values Helm upgrades,
disabled release removal, discovery failures, PodMonitor gating and node opt-out.
Additional CI checks cover read-only uninstall and single-node fallback in check
mode, and both remediation guards in check mode. Unexpected external commands fail
closed; expected guard failures must contain the relevant explanation.

For direct offline verification without Docker, with `ansible-playbook` and PyYAML
installed and on PATH:

```sh
python3 -m unittest discover -s molecule/default/tests -v
```

The direct command uses the same real role and assertions but does not verify the
two Ubuntu container environments. Neither command proves GPU-backed deployment
or live cordon/uncordon behavior.
