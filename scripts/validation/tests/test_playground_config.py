"""Render deployment boundaries; never run Docker or contact a host."""
import importlib.util
import json
import os
from pathlib import Path
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
    def render(self):
        path = ROLE / 'templates/compose.yml.j2'
        self.assertTrue(path.is_file(), 'private deployment template not implemented')
        defaults = yaml.safe_load((ROLE / 'defaults/main.yml').read_text())
        defaults['playground_model'] = defaults['playground_models']['qwen3']
        env = jinja2.Environment(undefined=jinja2.StrictUndefined)
        env.filters['to_json'] = json.dumps
        return yaml.safe_load(env.from_string(path.read_text()).render(**defaults))

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

    def test_webui_is_authenticated_and_single_backend_only(self):
        env = self.render()['services']['webui']['environment']
        self.assertEqual(env['WEBUI_AUTH'], 'true')
        self.assertEqual(env['OPENAI_API_BASE_URLS'], 'http://vllm:8000/v1')
        for name in ['ENABLE_SIGNUP', 'ENABLE_OLLAMA_API', 'ENABLE_WEB_SEARCH',
                     'ENABLE_IMAGE_GENERATION', 'ENABLE_DIRECT_CONNECTIONS', 'ENABLE_DIRECT_INTEGRATIONS',
                     'ENABLE_COMMUNITY_SHARING', 'ENABLE_PERSISTENT_CONFIG', 'ENABLE_CODE_EXECUTION']:
            self.assertEqual(env[name], 'false', name)
        for name in ['WEBUI_ADMIN_PASSWORD', 'OPENAI_API_KEYS', 'WEBUI_SECRET_KEY']:
            self.assertNotIn(name, env)

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
            with patch.object(module.os, 'execvp') as execute:
                module.launch('vllm', ['--model', '/models/snapshot'], root)
                argv = execute.call_args.args[1]
                self.assertEqual(argv[argv.index('--api-key') + 1], 'fixture-key')
                self.assertIn('/models/snapshot', argv)


if __name__ == '__main__':
    unittest.main()
