"""Execute real Ansible tasks against the bounded offline Kubernetes/Helm doubles."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent


class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.env = dict(os.environ, FAKE_STATE=str(self.state), RUNAI_TEST_BIN=str(HERE / 'bin'),
                        ANSIBLE_ROLES_PATH=str(ROOT / 'roles'), ANSIBLE_CONFIG=str(ROOT / 'ansible.cfg'))

    def play(self, remove=False, standard=False):
        play = 'site.yml' if standard else 'gateway.yml'
        opts = ['runai_state=absent'] if standard else ['runai_platform_exposure=gateway'] + (['runai_test_action=remove'] if remove else [])
        p = subprocess.run(['ansible-playbook', '-i', 'localhost,', str(HERE / play)] +
                           [a for opt in opts for a in ['-e', opt]], env=self.env, capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)

    def releases(self):
        return json.loads((self.state / 'releases.json').read_text())

    def test_foreign_controller_is_not_upgraded_or_removed(self):
        foreign = {'kgateway-system/' + n: {'ns': 'kgateway-system', 'chart': n + '-v1.0.0', 'values': {'foreign': True}}
                   for n in ('kgateway', 'kgateway-crds')}
        (self.state / 'releases.json').write_text(json.dumps(foreign))
        self.play()
        self.assertEqual(self.releases(), foreign)
        self.play(remove=True)
        self.assertEqual(self.releases(), foreign)

    def test_other_gateway_preserves_owned_controller(self):
        self.play()
        (self.state / 'foreign-gateway').write_text('1')
        self.play(remove=True)
        self.assertEqual(set(self.releases()), {'kgateway-system/kgateway', 'kgateway-system/kgateway-crds'})
        self.assertTrue((self.state / 'gwcrds').exists())

    def test_route_without_gateway_preserves_controller(self):
        self.play()
        (self.state / 'foreign-route').write_text('1')
        self.play(remove=True)
        self.assertEqual(set(self.releases()), {'kgateway-system/kgateway', 'kgateway-system/kgateway-crds'})
        self.assertTrue((self.state / 'gwcrds').exists())

    def test_failed_discovery_does_not_uninstall_controller(self):
        self.play()
        self.env['FAKE_DISCOVERY_FAIL'] = '1'
        p = subprocess.run(['ansible-playbook', '-i', 'localhost,', str(HERE / 'gateway.yml'),
                            '-e', 'runai_platform_exposure=gateway', '-e', 'runai_test_action=remove'],
                           env=self.env, capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(set(self.releases()), {'kgateway-system/kgateway', 'kgateway-system/kgateway-crds'})

    def test_owned_crd_query_preserves_jsonpath_argument(self):
        self.play()
        self.play(remove=True)
        calls = [json.loads(line) for line in
                 (self.state / 'kubectl-argv.jsonl').read_text().splitlines()]
        queries = [args for args in calls if args[:3] == ['get', 'crd', '--output']
                   and any(arg.startswith('jsonpath=') for arg in args)]
        # One argument must retain the range space, escaped annotation key,
        # quoted string comparison and newline escape, exactly as kubectl needs.
        self.assertEqual(queries, [[
            'get', 'crd', '--output',
            r'jsonpath={range .items[?(@.metadata.annotations.deepops\.nvidia\.com/runai-installed=="true")]}{.metadata.name}{"\n"}{end}',
        ]])

    def test_standard_absent_discovers_owned_gateway_install(self):
        self.play()
        self.play(standard=True)
        self.assertEqual(self.releases(), {})
        self.assertFalse((self.state / 'gwcrds').exists())
