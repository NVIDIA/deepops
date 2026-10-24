"""Whole-role offline Gateway install/rerun/remove, not Ansible --check.

Execute a temporary role copy with ONLY root ownership mapped to the invoking
user and /etc/hosts redirected into the fixture. All task logic, shell parsing,
filters, TLS generation and the API helper remain real. External Kubernetes,
Helm and HTTP operations are bounded doubles; nothing contacts a cluster.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent


class PlatformPath(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='runai-platform-')
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name)
        role = self.state / 'roles/runai'
        shutil.copytree(ROOT / 'roles/runai', role)
        for path in (role / 'tasks').glob('*.yml'):
            text = path.read_text().replace('owner: root', 'owner: "%s"' % os.getuid())
            text = text.replace('group: root', 'group: "%s"' % os.getgid())
            text = text.replace('path: /etc/hosts', 'path: "' + str(self.state / 'hosts') + '"')
            path.write_text(text)
        (self.state / 'hosts').write_text('127.0.0.1 localhost\n')
        self.prerequisite = {'monitoring/kube-prometheus-stack': {
            'ns': 'monitoring', 'chart': 'kube-prometheus-stack-88.6.5', 'values': {}}}
        (self.state / 'releases.json').write_text(json.dumps(self.prerequisite))
        self.playbook = self.state / 'site.yml'
        self.playbook.write_text(yaml.safe_dump([{
            'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
            'vars': {
                'ansible_become': False, 'ansible_python_interpreter': sys.executable,
                'runai_kubectl': str(HERE / 'bin/kubectl'), 'runai_helm': str(HERE / 'bin/helm'),
                'runai_work_dir': str(self.state / 'work'),
                'runai_mode': 'platform', 'runai_platform_exposure': 'gateway',
                'runai_platform_domain': 'runai.lab.test',
                'runai_platform_admin_password': 'Offline-test1!',
                'runai_platform_manage_hosts_entry': True,
                'runai_platform_coredns_rewrite': True,
                'runai_platform_address_timeout': 1,
            }, 'roles': ['runai'],
        }]))
        self.env = dict(os.environ, FAKE_STATE=str(self.state),
                        PATH=str(HERE / 'bin') + os.pathsep + os.environ['PATH'],
                        ANSIBLE_CONFIG=str(ROOT / 'ansible.cfg'),
                        ANSIBLE_ROLES_PATH=str(self.state / 'roles'))

    def play(self, *extra):
        result = subprocess.run(['ansible-playbook', '-i', 'localhost,', str(self.playbook), *extra],
                                env=self.env, capture_output=True, text=True, timeout=180)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def read_json(self, name):
        return json.loads((self.state / name).read_text())

    def calls(self, name):
        return [json.loads(line) for line in (self.state / name).read_text().splitlines()]

    def check_round_trip(self, routing):
        extra = ['-e', 'runai_gateway_workload_routing=' + routing]
        self.play(*extra)
        releases = self.read_json('releases.json')
        self.assertEqual(set(releases) - set(self.prerequisite), {
            'kgateway-system/kgateway', 'kgateway-system/kgateway-crds',
            'runai-backend/runai-backend', 'runai/runai-cluster'})
        cp = releases['runai-backend/runai-backend']['values']['global']
        cluster = releases['runai/runai-cluster']['values']
        self.assertFalse(cp['ingress']['enabled'])
        self.assertTrue(cp['gatewayAPI']['enabled'])
        self.assertEqual(cluster['controlPlane']['url'], 'https://runai.lab.test')
        self.assertEqual(cluster['cluster']['uid'], 'offline-cluster')
        self.assertEqual(cluster['clusterConfig']['global']['subdomainSupport'], routing == 'host')
        manifests = self.read_json('manifests.json')
        gateway = manifests['Gateway/runai/runai-gateway']
        self.assertEqual(len(gateway['spec']['listeners']), 2 if routing == 'host' else 1)
        for listener in gateway['spec']['listeners']:
            for cert in listener['tls']['certificateRefs']:
                self.assertIn('Secret/runai/' + cert['name'], manifests)
        for cm in ('coredns', 'nodelocaldns'):
            self.assertIn('192.0.2.50 runai.lab.test', (self.state / cm).read_text())
        self.assertIn('192.0.2.50 runai.lab.test', (self.state / 'hosts').read_text())
        upgrades = [a for a in self.calls('helm-argv.jsonl') if a[0] == 'upgrade']
        api_calls = self.calls('api-calls.jsonl')
        self.assertEqual(len(upgrades), 4)
        self.assertEqual(len(api_calls), 4)
        # Exercise supplied-certificate selection on the converged rerun too.
        self.play(*extra, '-e', 'runai_platform_tls_cert_file=' + str(self.state / 'work/tls.crt'),
                  '-e', 'runai_platform_tls_key_file=' + str(self.state / 'work/tls.key'),
                  '-e', 'runai_platform_ca_file=' + str(self.state / 'work/ca.pem'))
        self.assertEqual([a for a in self.calls('helm-argv.jsonl') if a[0] == 'upgrade'], upgrades)
        self.assertEqual(self.calls('api-calls.jsonl'), api_calls)
        self.play('-e', 'runai_state=absent')
        self.assertEqual(self.read_json('releases.json'), self.prerequisite)
        self.assertFalse((self.state / 'gateway').exists())
        self.assertFalse((self.state / 'gwcrds').exists())
        for cm in ('coredns', 'nodelocaldns', 'hosts'):
            self.assertNotIn('deepops-runai', (self.state / cm).read_text())
        self.play('-e', 'runai_state=absent')
        self.assertEqual(self.read_json('releases.json'), self.prerequisite)

    def test_gateway_absent_does_not_delete_ingress_namespace(self):
        self.play('-e', 'runai_state=absent')
        deletions = [a[2] for a in self.calls('kubectl-argv.jsonl') if a[:2] == ['delete', 'namespace']]
        self.assertEqual(deletions, ['kai-scheduler', 'kai-resource-reservation',
                                    'runai-reservation', 'runai-scale-adjust', 'runai', 'runai-backend'])

    def test_ingress_absent_still_deletes_managed_ingress_namespace(self):
        self.play('-e', 'runai_state=absent', '-e', 'runai_platform_exposure=ingress')
        deletions = [a[2] for a in self.calls('kubectl-argv.jsonl') if a[:2] == ['delete', 'namespace']]
        self.assertEqual(deletions[-1], 'haproxy-controller')
        self.assertEqual(len(deletions), 7)

    def test_path_routing_full_install_rerun_remove(self):
        self.check_round_trip('path')

    def test_host_routing_full_install_rerun_remove(self):
        self.check_round_trip('host')


if __name__ == '__main__':
    unittest.main()
