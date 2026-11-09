#!/usr/bin/env python3
"""Run the real role against strict command stubs; never contact Kubernetes.

Requires ansible-playbook and PyYAML. Run: python3 -m unittest discover
-s roles/nvsentinel/tests -v. The stub is only the external kubectl/Helm boundary.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[3]
STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
kind = pathlib.Path(sys.argv[0]).name
state = json.loads(pathlib.Path(os.environ['NVS_TEST_STATE']).read_text())
with open(os.environ['NVS_TEST_TRACE'], 'a') as f:
    f.write(json.dumps([kind, *args]) + '\n')
def emit(value):
    print(json.dumps(value))
    sys.exit(0)
def fail():
    print('fixture API access denied', file=sys.stderr)
    sys.exit(1)
if kind == 'kubectl':
    if args == ['version', '-o', 'json']:
        emit({'serverVersion': {'gitVersion': state.get('version', 'v1.35.0')}})
    if args == ['get', 'nodes', '-l', 'nvidia.com/gpu.present=true', '-o', 'json']:
        if state.get('node_error'): fail()
        emit({'apiVersion': 'v1', 'kind': 'List', 'items': [
            {'metadata': {'name': 'gpu-' + str(i), 'labels': {'nvidia.com/gpu.present': 'true'}}}
            for i in range(state.get('nodes', 3))]})
    if args == ['get', 'crd', 'podmonitors.monitoring.coreos.com', '--ignore-not-found', '-o', 'json']:
        if state.get('crd_error'): fail()
        print(json.dumps({'metadata': {'name': 'podmonitors.monitoring.coreos.com'}})
              if state.get('podmonitor', False) else '')
        sys.exit(0)
    if args == ['get', 'nodes', '-o', 'json']:
        emit({'items': [{'metadata': {'name': 'gpu-0'}}, {'metadata': {'name': 'cpu-0'}}]})
    if args[:3] == ['label', 'node', 'gpu-0'] and args[3:] == ['nvsentinel.dgxc.nvidia.com/managed=false', '--overwrite']:
        print('node/gpu-0 labeled'); sys.exit(0)
    if args == ['get', 'storageclass', 'local-path', '-o', 'name']:
        if state.get('storage_error'): fail()
        print('storageclass.storage.k8s.io/local-path'); sys.exit(0)
    if args == ['-n', 'cert-manager', 'get', 'deployment', 'cert-manager', '-o', 'jsonpath={.spec.template.spec.containers[0].image}']:
        print('quay.io/jetstack/cert-manager-controller:v1.21.1'); sys.exit(0)
    if args == ['get', 'crd', 'certificates.cert-manager.io', '-o', 'name']:
        print('customresourcedefinition.apiextensions.k8s.io/certificates.cert-manager.io'); sys.exit(0)
if kind == 'helm':
    if args[:1] == ['list']:
        if state.get('helm_error'): fail()
        emit([{'name': 'nvsentinel', 'status': 'deployed'}] if state.get('installed', True) else [])
    if args[:2] == ['upgrade', '--install']:
        if state.get('helm_error'): fail()
        value_file = pathlib.Path(args[args.index('--values') + 1])
        pathlib.Path(os.environ['NVS_TEST_VALUES']).write_text(value_file.read_text())
        print('fixture Helm install complete'); sys.exit(0)
    if args[:1] == ['uninstall']:
        if state.get('helm_error'): fail()
        print('release uninstalled'); sys.exit(0)
print('unexpected stub command: ' + repr([kind, *args]), file=sys.stderr)
sys.exit(90)
'''


class RoleTests(unittest.TestCase):
    def run_role(self, variables=None, state=None, check=False, unmanaged=False):
        with tempfile.TemporaryDirectory(prefix='nvsentinel-role-') as tmp:
            tmp = Path(tmp)
            for name in ('kubectl', 'helm'):
                path = tmp / name
                path.write_text(STUB)
                path.chmod(0o755)
            (tmp / 'state.json').write_text(json.dumps(state or {}))
            inventory = {'all': {'hosts': {'localhost': {'ansible_connection': 'local'}},
                                 'children': {'k8s_cluster': {'hosts': {
                                     'gpu-inventory': {'kube_override_hostname': 'gpu-0',
                                                       'nvsentinel_unmanaged': unmanaged},
                                     'cpu-0': {}}}}}}
            (tmp / 'inventory.yml').write_text(yaml.safe_dump(inventory))
            play = [{'hosts': 'localhost', 'gather_facts': False, 'environment': {
                'NVS_TEST_STATE': str(tmp / 'state.json'),
                'NVS_TEST_TRACE': str(tmp / 'trace'),
                'NVS_TEST_VALUES': str(tmp / 'observed.yml')},
                'roles': ['nvsentinel']}]
            (tmp / 'play.yml').write_text(yaml.safe_dump(play))
            extra = {'nvsentinel_kubectl_binary': str(tmp / 'kubectl'),
                     'nvsentinel_helm_binary': str(tmp / 'helm'),
                     'nvsentinel_config_dir': str(tmp / 'config'),
                     'nvsentinel_kubeconfig': str(tmp / 'no-real-kubeconfig')}
            extra.update(variables or {})
            (tmp / 'vars.json').write_text(json.dumps(extra))
            (tmp / 'ansible.cfg').write_text('[defaults]\nhost_key_checking=False\nretry_files_enabled=False\n')
            env = {**os.environ, 'ANSIBLE_CONFIG': str(tmp / 'ansible.cfg'),
                   'ANSIBLE_ROLES_PATH': str(ROOT / 'roles'), 'ANSIBLE_NOCOLOR': '1',
                   'ANSIBLE_LOCAL_TEMP': str(tmp / 'ansible-local')}
            command = [shutil.which('ansible-playbook'), '-i', str(tmp / 'inventory.yml'),
                       str(tmp / 'play.yml'), '-e', '@' + str(tmp / 'vars.json')]
            if check:
                command.append('--check')
            result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=90)
            output = result.stdout + result.stderr
            trace = [json.loads(x) for x in (tmp / 'trace').read_text().splitlines()] if (tmp / 'trace').exists() else []
            values = yaml.safe_load((tmp / 'observed.yml').read_text()) if (tmp / 'observed.yml').exists() else None
            return result.returncode, output, trace, values

    def assert_no_writes(self, trace):
        self.assertFalse([x for x in trace if x[1] in ('label', 'upgrade', 'uninstall', 'apply', 'create', 'delete')], trace)

    def test_unsafe_modes_fail_before_writes(self):
        for variables, message in [
            ({'nvsentinel_mode': 'invalid'}, 'nvsentinel_mode'),
            ({'nvsentinel_mode': 'remediate'}, 'nvsentinel_allow_node_reboot'),
            ({'nvsentinel_mode': 'remediate', 'nvsentinel_allow_node_reboot': True,
              'nvsentinel_dry_run': True}, 'dry-run'),
        ]:
            with self.subTest(variables=variables):
                rc, output, trace, _ = self.run_role(variables, {'nodes': 1})
                self.assertNotEqual(rc, 0, output)
                self.assertIn(message, output)
                self.assert_no_writes(trace)

    def test_internal_overrides_cannot_bypass_discovery(self):
        cases = [
            ({'nvsentinel_effective_mode': 'remediate'}, {}),
            ({'nvsentinel_effective_mode': 'remediate',
              'nvsentinel_allow_node_reboot': True, 'nvsentinel_dry_run': True}, {}),
            ({'nvsentinel_effective_mode': 'cordon'}, {'nodes': 1}),
            ({'nvsentinel_effective_gpu_node_count': 3}, {'nodes': 1}),
            ({'nvsentinel_effective_gpu_node_count': 3}, {'nodes': 0}),
            ({'nvsentinel_pod_monitor_available': True}, {'podmonitor': False}),
        ]
        for variables, state in cases:
            with self.subTest(variables=variables, state=state):
                rc, output, trace, values = self.run_role(variables, state)
                self.assertNotEqual(rc, 0, output)
                self.assertIn('role-resolved', output)
                self.assert_no_writes(trace)
                self.assertIsNone(values)
        rc, output, trace, _ = self.run_role(
            {'nvsentinel_effective_mode': 'remediate'}, check=True)
        self.assertNotEqual(rc, 0, output)
        self.assert_no_writes(trace)

    def test_exclusions_reject_malformed_selectors_before_writes(self):
        for exclusions in ['bad', {}, ['bad'], [{'unknown': 'field'}],
                           [{'matchLabels': ['bad']}], [{'matchLabels': {'zone': 1}}],
                           [{'matchExpressions': 'bad'}],
                           [{'matchExpressions': [{'key': 'zone', 'operator': 'Invalid'}]}],
                           [{'matchExpressions': [{'key': 'zone', 'operator': 'In', 'values': []}]}],
                           [{'matchExpressions': [{'key': 'zone', 'operator': 'Exists', 'values': ['a']}]}]]:
            with self.subTest(exclusions=exclusions):
                rc, output, trace, _ = self.run_role(
                    {'nvsentinel_janitor_extra_exclusions': exclusions})
                self.assertNotEqual(rc, 0, output)
                self.assertIn('exclusion', output.lower())
                self.assert_no_writes(trace)

    def test_exclusions_preserve_valid_selectors_and_control_plane(self):
        exclusions = [{'matchLabels': {'zone': 'a'}},
                      {'matchExpressions': [{'key': 'zone', 'operator': 'In', 'values': ['b']},
                                            {'key': 'maintenance', 'operator': 'Exists'}]}]
        rc, output, _, values = self.run_role({'nvsentinel_janitor_extra_exclusions': exclusions})
        self.assertEqual(rc, 0, output)
        self.assertEqual(values['janitor']['config']['nodes']['exclusions'],
                         [{'matchLabels': {'node-role.kubernetes.io/control-plane': ''}}, *exclusions])

    def test_zero_or_invalid_count_fails(self):
        for variables, state in [({}, {'nodes': 0}),
                                 ({'nvsentinel_gpu_node_count': 0}, {}),
                                 ({'nvsentinel_gpu_node_count': -1}, {}),
                                 ({'nvsentinel_gpu_node_count': 'bad'}, {}),
                                 ({'nvsentinel_gpu_node_count': 1.5}, {})]:
            with self.subTest(variables=variables, state=state):
                rc, output, trace, _ = self.run_role(variables, state)
                self.assertNotEqual(rc, 0, output)
                self.assertIn('GPU node', output)
                self.assert_no_writes(trace)

    def test_single_gpu_extra_var_steps_down_before_prereqs(self):
        rc, output, trace, values = self.run_role({'nvsentinel_mode': 'cordon'}, {'nodes': 1})
        self.assertEqual(rc, 0, output)
        self.assertIsNotNone(values, output)
        self.assertFalse(values['global']['faultQuarantine']['enabled'])
        self.assertFalse(values['global']['mongodbStore']['enabled'])
        self.assertIn('observe', output)
        self.assertFalse(any('cert-manager' in x for x in trace), trace)
        self.assertIn(['kubectl', 'get', 'nodes', '-l', 'nvidia.com/gpu.present=true', '-o', 'json'], trace)

    def test_count_override_force_and_full_values(self):
        for variables, state, expected_percentage in [
            ({}, {'nodes': 3}, 100),
            ({'nvsentinel_gpu_node_count': 12}, {'nodes': 0}, 50),
            ({'nvsentinel_mode_force': True}, {'nodes': 1}, 100),
        ]:
            with self.subTest(variables=variables):
                rc, output, trace, values = self.run_role(variables, state)
                self.assertEqual(rc, 0, output)
                self.assertIsNotNone(values, output)
                self.assertTrue(values['global']['faultQuarantine']['enabled'])
                self.assertFalse(values['global']['nodeDrainer']['enabled'])
                self.assertFalse(values['global']['janitor']['enabled'])
                self.assertEqual(values['fault-quarantine']['circuitBreaker']['percentage'], expected_percentage)
                install = next(x for x in trace if x[1:3] == ['upgrade', '--install'])
                self.assertIn('--reset-values', install)
                self.assertNotIn('--reuse-values', install)
                self.assertIn('v1.27.0', install)
                self.assertNotIn('systemUsers', values['mongodb-store']['psmdb-db'])
                self.assertFalse(any('secret' in x for x in trace))

    def test_podmonitor_crd_gates_even_explicit_enable(self):
        for exists in (False, True):
            rc, output, _, values = self.run_role({'nvsentinel_mode': 'observe', 'nvsentinel_pod_monitor': True,
                                                  'gpu_operator_preinstalled_nvidia_software': False},
                                                 {'podmonitor': exists})
            self.assertEqual(rc, 0, output)
            self.assertIsNotNone(values, output)
            self.assertEqual(values['podMonitor']['enabled'], exists)
            self.assertFalse(values['labeler']['assumeDriverInstalled'])

    def test_api_and_version_errors_fail_closed(self):
        for state in ({'node_error': True}, {'crd_error': True}, {'version': 'v1.33.9'},
                      {'storage_error': True}, {'version': 'v1.34.0-alpha.1'}):
            with self.subTest(state=state):
                rc, output, trace, _ = self.run_role(state=state)
                self.assertNotEqual(rc, 0, output)
                self.assert_no_writes(trace)

    def test_optout_precedes_install(self):
        rc, output, trace, _ = self.run_role(unmanaged=True)
        self.assertEqual(rc, 0, output)
        label = ['kubectl', 'label', 'node', 'gpu-0', 'nvsentinel.dgxc.nvidia.com/managed=false', '--overwrite']
        self.assertIn(label, trace)
        install_index = next(i for i, x in enumerate(trace) if x[1] == 'upgrade')
        self.assertLess(trace.index(label), install_index)

    def test_check_mode_reads_and_validates_without_writes(self):
        rc, output, trace, values = self.run_role(check=True, unmanaged=True)
        self.assertEqual(rc, 0, output)
        self.assertIn(['kubectl', 'version', '-o', 'json'], trace)
        self.assert_no_writes(trace)
        self.assertIsNone(values)
        rc, output, trace, _ = self.run_role({'nvsentinel_mode': 'remediate'}, check=True)
        self.assertNotEqual(rc, 0, output)
        self.assert_no_writes(trace)

    def test_disabled_uninstalls_only_release_and_ignores_install_guards(self):
        for installed in (False, True):
            rc, output, trace, values = self.run_role(
                {'nvsentinel_enabled': False, 'nvsentinel_mode': 'invalid'},
                {'installed': installed, 'nodes': 0, 'version': 'v1.30.0'})
            self.assertEqual(rc, 0, output)
            self.assertTrue(trace, output)
            self.assertTrue(all(x[0] == 'helm' for x in trace), trace)
            self.assertEqual(sum(x[1] == 'uninstall' for x in trace), int(installed))
            self.assertIsNone(values)
        rc, output, trace, _ = self.run_role({'nvsentinel_enabled': False}, {'helm_error': True})
        self.assertNotEqual(rc, 0, output)
        self.assert_no_writes(trace)


if __name__ == '__main__':
    unittest.main()
