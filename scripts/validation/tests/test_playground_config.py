"""Render deployment boundaries; never run Docker or contact a host."""
import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import jinja2
import yaml

ROOT = Path(__file__).resolve().parents[3]
ROLE = ROOT / 'roles/model_playground'
sys.path.insert(0, str(ROOT / 'scripts/validation'))


class DeploymentContractTests(unittest.TestCase):
    def render(self, profile='qwen3'):
        path = ROLE / 'templates/compose.yml.j2'
        self.assertTrue(path.is_file(), 'private deployment template not implemented')
        defaults = yaml.safe_load((ROLE / 'defaults/main.yml').read_text())
        defaults['playground_model'] = defaults['playground_models'][profile]
        env = jinja2.Environment(undefined=jinja2.StrictUndefined)
        env.filters['to_json'] = json.dumps
        return yaml.safe_load(env.from_string(path.read_text()).render(**defaults))

    def vllm_parser(self):
        fixture = json.loads((Path(__file__).parent / 'fixtures/vllm-0.31.0-playground-args.json').read_text())
        image = self.render()['services']['vllm']['image']
        self.assertTrue(image.startswith('vllm/vllm-openai:v' + fixture['version'] + '@sha256:'))
        parser = argparse.ArgumentParser(allow_abbrev=False)
        types = {'str': str, 'int': int, 'float': float}
        for flag, kind in fixture['arguments'].items():
            parser.add_argument(flag, type=types[kind], required=True)
        return parser

    def test_every_rendered_vllm_argument_is_supported_by_pinned_version(self):
        for profile in ['qwen3', 'gpt-oss']:
            with self.subTest(profile=profile):
                self.vllm_parser().parse_args(self.render(profile)['services']['vllm']['command'])

    def test_pinned_argument_check_rejects_unknown_flags(self):
        command = self.render()['services']['vllm']['command']
        for flag in ['--disable-log-requests', '--unknown-option', '--max-model']:
            with self.subTest(flag=flag), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    self.vllm_parser().parse_args(command + [flag])
                self.assertEqual(error.exception.code, 2)

    def test_only_gateway_publishes_and_inference_has_no_egress(self):
        config = self.render()
        services = config['services']
        self.assertTrue(config['networks']['private']['internal'])
        for name in ['vllm', 'webui']:
            self.assertNotIn('ports', services[name])
            self.assertEqual(services[name]['networks'], ['private'])
            self.assertNotIn('network_mode', services[name])
        self.assertEqual(services['gateway']['ports'], ['127.0.0.1:8443:443'])
        self.assertEqual(services['vllm']['environment']['HF_HUB_OFFLINE'], '1')
        self.assertIn('/var/lib/deepops/model-playground/cache:/models:ro', services['vllm']['volumes'])
        for service in services.values():
            self.assertEqual(service['restart'], 'unless-stopped')
            self.assertIn('@sha256:', service['image'])

    def tls_san(self, name, bind='127.0.0.1'):
        tasks = yaml.safe_load((ROLE / 'tasks/deploy.yml').read_text())
        task = next(t for t in tasks if t.get('name') == 'Compute certificate identities')
        env = jinja2.Environment(undefined=jinja2.StrictUndefined)
        env.tests['match'] = lambda value, pattern: re.match(pattern, value) is not None
        expression = task['ansible.builtin.set_fact']['playground_tls_san']
        return env.from_string(expression).render(
            playground_tls_name=name, playground_bind_address=bind,
            **task['vars']).strip()

    def test_certificate_identities_use_ip_sans_for_addresses(self):
        cases = {
            ('localhost', '127.0.0.1'): 'DNS:localhost,IP:127.0.0.1',
            ('playground.example.org', '10.0.0.5'): 'DNS:playground.example.org,IP:10.0.0.5,DNS:localhost,IP:127.0.0.1',
            ('10.0.0.5', '10.0.0.5'): 'IP:10.0.0.5,DNS:localhost,IP:127.0.0.1',
            ('10.0.0.5', '127.0.0.1'): 'IP:10.0.0.5,DNS:localhost,IP:127.0.0.1',
            ('10.0.0.256', '127.0.0.1'): 'DNS:10.0.0.256,DNS:localhost,IP:127.0.0.1',
        }
        for (name, bind), expected in cases.items():
            with self.subTest(name=name, bind=bind):
                self.assertEqual(self.tls_san(name, bind), expected)
        argv = next(t['ansible.builtin.command']['argv'] for t in yaml.safe_load((ROLE / 'tasks/deploy.yml').read_text())
                    if t.get('name') == 'Generate a private self-signed HTTPS certificate')
        self.assertIn('subjectAltName={{ playground_tls_san }}', argv)

    @unittest.skipUnless(shutil.which('openssl'), 'openssl not installed')
    def test_private_ip_certificate_verifies_by_ip(self):
        san = self.tls_san('10.0.0.5', '10.0.0.5')
        with tempfile.TemporaryDirectory() as tmp:
            key, cert = Path(tmp) / 'key.pem', Path(tmp) / 'cert.pem'
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                            '-keyout', str(key), '-out', str(cert), '-subj', '/CN=10.0.0.5',
                            '-addext', 'subjectAltName=' + san], check=True, capture_output=True)
            for ip, ok in [('10.0.0.5', True), ('127.0.0.1', True), ('10.0.0.6', False)]:
                with self.subTest(ip=ip):
                    result = subprocess.run(['openssl', 'verify', '-CAfile', str(cert), '-verify_ip', ip, str(cert)],
                                            capture_output=True)
                    self.assertEqual(result.returncode == 0, ok)

    def test_command_arguments_parse_as_intended(self):
        commands = {}
        for path in sorted((ROLE / 'tasks').glob('*.yml')):
            for task in yaml.safe_load(path.read_text()) or []:
                argv = (task.get('ansible.builtin.command') or {}).get('argv')
                if isinstance(argv, list):
                    commands[task.get('name')] = argv
                    for item in argv:
                        # An unquoted comma in a YAML flow list silently splits one argument.
                        self.assertFalse(str(item) in {'noheader', 'nounits'}, (task.get('name'), argv))
        self.assertEqual(commands['Verify exactly one visible GPU and an already configured driver'],
                         ['nvidia-smi', '--query-gpu=uuid', '--format=csv,noheader'])

    def test_webui_is_authenticated_and_single_backend_only(self):
        env = self.render()['services']['webui']['environment']
        self.assertEqual(env['WEBUI_AUTH'], 'true')
        self.assertEqual(env.get('BYPASS_MODEL_ACCESS_CONTROL', 'false'), 'false')
        self.assertEqual(env['OPENAI_API_BASE_URLS'], 'http://vllm:8000/v1')
        for name in ['ENABLE_SIGNUP', 'ENABLE_OLLAMA_API', 'ENABLE_WEB_SEARCH',
                     'ENABLE_IMAGE_GENERATION', 'ENABLE_DIRECT_CONNECTIONS', 'ENABLE_DIRECT_INTEGRATIONS',
                     'ENABLE_COMMUNITY_SHARING', 'ENABLE_PERSISTENT_CONFIG', 'ENABLE_CODE_EXECUTION']:
            self.assertEqual(env[name], 'false', name)
        for name in ['WEBUI_ADMIN_PASSWORD', 'OPENAI_API_KEYS', 'WEBUI_SECRET_KEY']:
            self.assertNotIn(name, env)

    def test_deploy_bootstraps_selected_model_before_validation_and_gateway(self):
        tasks = yaml.safe_load((ROLE / 'tasks/deploy.yml').read_text())
        commands = [t['ansible.builtin.command']['argv'] for t in tasks
                    if 'ansible.builtin.command' in t and isinstance(t['ansible.builtin.command']['argv'], list)]
        bootstrap = next(c for c in commands if 'bootstrap' in c)
        validate = next(c for c in commands if '/opt/playground/validate_playground.py' in c)
        gateway = next(c for c in commands if c[-3:] == ['up', '-d', 'gateway'])
        self.assertIn('--model', bootstrap)
        self.assertEqual(bootstrap[bootstrap.index('--model') + 1], '{{ playground_model.served_name }}')
        self.assertEqual(validate[validate.index('--user-file') + 1], '/run/playground/user.json')
        self.assertLess(commands.index(bootstrap), commands.index(validate))
        self.assertLess(commands.index(validate), commands.index(gateway))

    def test_launch_reads_private_files_not_compose_secrets(self):
        path = ROLE / 'files/playground_entrypoint.py'
        self.assertTrue(path.is_file(), 'private entrypoint not implemented')
        spec = importlib.util.spec_from_file_location('playground_entrypoint', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, value in [('api-key', 'fixture-key'), ('webui-key', 'fixture-session'),
                                ('admin.json', json.dumps({'email': 'admin@example.org', 'password': 'fixture-password'}))]:
                p = root / name
                p.write_text(value)
                p.chmod(0o600)
            with patch.dict(os.environ, {}, clear=True), patch.object(module.os, 'execvp') as execute:
                module.launch('webui', [], root)
                self.assertEqual(os.environ['OPENAI_API_KEYS'], 'fixture-key')
                self.assertEqual(os.environ['WEBUI_ADMIN_PASSWORD'], 'fixture-password')
                self.assertEqual(execute.call_args.args, ('bash', ['bash', '/app/backend/start.sh']))
            with patch.dict(os.environ, {}, clear=True), patch.object(module.os, 'execvp') as execute:
                command = self.render()['services']['vllm']['command']
                module.launch('vllm', command, root)
                argv = execute.call_args.args[1]
                self.assertEqual(os.environ.get('VLLM_API_KEY'), 'fixture-key')
                self.assertNotIn('fixture-key', argv)
                self.assertNotIn('--api-key', argv)
                self.assertEqual(argv[:3], ['python3', '-m', 'vllm.entrypoints.openai.api_server'])
                self.vllm_parser().parse_args(argv[3:])


if __name__ == '__main__':
    unittest.main()
