"""Tests deploy_monitoring.sh exit codes using stubbed helm/kubectl (no cluster).

Run with: python3 -m unittest discover scripts/validation/tests
"""

import os
import shutil
import stat
import subprocess
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SCRIPT = os.path.join(REPO, "scripts", "k8s", "deploy_monitoring.sh")

HELM = r"""#!/bin/bash
echo "helm $*" >> "$STUB_LOG"
case "$1" in
  repo) [ "$2" = list ] && echo prometheus-community; exit 0 ;;
  list)
    [ "${LIST_RC:-0}" != 0 ] && exit "$LIST_RC"
    [ -n "$STATUS_BEFORE" ] && echo kube-prometheus-stack
    exit 0 ;;
  status)
    [ "${STATUS_RC:-0}" != 0 ] && exit "$STATUS_RC"
    n=$(cat "$STUB_STATE" 2>/dev/null || echo 0)
    [ "$n" -lt 1 ] && [ -z "$STATUS_BEFORE" ] && exit 1
    if [ "$n" -ge 1 ]; then s="$STATUS_AFTER"; else s="$STATUS_BEFORE"; fi
    echo "{\"info\": {\"status\": \"$s\"}}"; exit 0 ;;
  install|upgrade)
    printf '%s\0' "$@" > "$STUB_ARGS"
    echo 1 > "$STUB_STATE"; exit "${UPGRADE_RC:-0}" ;;
esac
exit 0
"""
KUBECTL = r"""#!/bin/bash
echo "kubectl $*" >> "$STUB_LOG"
[ "$1 $2" = "get storageclass" ] && echo "standard (default)"
exit 0
"""


class TestDeployMonitoringExit(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        k8s = os.path.join(self.tmp, "scripts", "k8s")
        os.makedirs(k8s)
        os.makedirs(os.path.join(self.tmp, "config"))
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(self.bin)
        shutil.copy(SCRIPT, k8s)
        self.write(os.path.join(self.tmp, "scripts", "common.sh"), "")
        for name in ("deploy_ingress.sh", "install_helm.sh"):
            self.write(os.path.join(k8s, name), "#!/bin/bash\nexit 0\n")
        self.write(os.path.join(self.bin, "helm"), HELM)
        self.write(os.path.join(self.bin, "kubectl"), KUBECTL)
        self.log = os.path.join(self.tmp, "log")
        self.state = os.path.join(self.tmp, "state")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    @staticmethod
    def write(path, text):
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)

    def run_script(self, args=(), **env):
        e = dict(os.environ, PATH=self.bin + ":" + os.environ["PATH"],
                 STUB_LOG=self.log, STUB_STATE=self.state,
                 STUB_ARGS=os.path.join(self.tmp, "helm-args"), **env)
        r = subprocess.run(["bash", os.path.join(self.tmp, "scripts", "k8s", "deploy_monitoring.sh"), *args],
                           cwd=self.tmp, env=e, capture_output=True, text=True, timeout=60)
        calls = ""
        if os.path.exists(self.log):
            with open(self.log) as log:
                calls = log.read()
        return r, calls

    def test_reset_deletes_all_monitoring_crds(self):
        r, calls = self.run_script(args=("-d",))
        self.assertEqual(r.returncode, 0, r.stderr)
        deleted = {line.removeprefix("kubectl delete crd ")
                   for line in calls.splitlines() if line.startswith("kubectl delete crd ")}
        self.assertEqual(deleted, {name + ".monitoring.coreos.com" for name in (
            "alertmanagerconfigs", "alertmanagers", "podmonitors", "probes",
            "prometheusagents", "prometheuses", "prometheusrules", "scrapeconfigs",
            "servicemonitors", "thanosrulers")})

    def test_fresh_install_succeeds(self):
        r, calls = self.run_script(STATUS_AFTER="deployed")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("helm install", calls)
        self.assertNotIn("helm upgrade", calls)
        self.assertNotIn("kubectl apply", calls)

    def test_already_deployed_skips_install(self):
        r, calls = self.run_script(STATUS_BEFORE="deployed", STATUS_AFTER="deployed")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("helm upgrade", calls)
        self.assertNotIn("helm install", calls)
        self.assertNotIn("kubectl apply", calls)

    def test_helm_upgrade_failure_exits_nonzero(self):
        r, _ = self.run_script(UPGRADE_RC="1", STATUS_AFTER="failed")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("failed", r.stderr)

    def test_release_left_failed_exits_nonzero(self):
        r, _ = self.run_script(STATUS_AFTER="failed")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("not in 'deployed' state", r.stderr)

    def test_existing_unhealthy_release_requires_manual_crd_first_retry(self):
        # An existing 88.6.5 release must never reach a workload upgrade
        # without the manually reviewed exact-package CRD-first procedure.
        for state in ("failed", "pending-upgrade", "uninstalled", "unknown"):
            with self.subTest(state=state):
                r, calls = self.run_script(STATUS_BEFORE=state, STATUS_AFTER="deployed")
                self.assertNotEqual(r.returncode, 0)
                self.assertIn("CRD-first", r.stderr)
                self.assertIn("monitoring-upgrade-92.md", r.stderr)
                self.assertNotIn("helm upgrade", calls)
                self.assertNotIn("helm install", calls)
                self.assertNotIn("kubectl apply", calls)

    def test_release_list_failure_does_not_install(self):
        r, calls = self.run_script(LIST_RC="1")
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("helm install", calls)
        self.assertNotIn("helm upgrade", calls)

    def test_existing_release_status_failure_does_not_install(self):
        r, calls = self.run_script(STATUS_BEFORE="failed", STATUS_RC="1")
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("helm install", calls)
        self.assertNotIn("helm upgrade", calls)

    def test_explicit_chart_version_is_used(self):
        r, calls = self.run_script(STATUS_AFTER="deployed", HELM_PROMETHEUS_CHART_VERSION="88.6.5")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("--version 88.6.5", calls)

    def test_invalid_mirror_fails_before_workload_install(self):
        for reference in ("https://mirror.example/image", "mirror.example/", "mirror.example/image,other=value"):
            with self.subTest(reference=reference):
                r, calls = self.run_script(STATUS_AFTER="deployed", PROMETHEUS_REPO=reference)
                self.assertNotEqual(r.returncode, 0)
                self.assertNotIn("helm install", calls)
                self.assertNotIn("helm upgrade", calls)


if __name__ == "__main__":
    unittest.main()
