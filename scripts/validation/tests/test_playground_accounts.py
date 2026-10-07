"""Test secret creation and account bootstrap without an Open WebUI deployment."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts/validation'))


class AccountTests(unittest.TestCase):
    def setUp(self):
        path = ROOT / 'roles/model_playground/files/playground_accounts.py'
        self.assertTrue(path.is_file(), 'account provisioning helper is not implemented')
        spec = importlib.util.spec_from_file_location('playground_accounts', path)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'secrets'

    def test_secrets_private_and_stable_on_rerun(self):
        self.module.initialize(self.root, 'admin@example.org', 'reader@example.org', 'Reader')
        before = {p.name: p.read_bytes() for p in self.root.iterdir()}
        self.module.initialize(self.root, 'admin@example.org', 'reader@example.org', 'Reader')
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.root.iterdir()})
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o700)
        for p in self.root.iterdir():
            self.assertEqual(stat.S_IMODE(p.stat().st_mode), 0o600)
        self.assertNotEqual(json.loads(before['admin.json'])['password'], json.loads(before['user.json'])['password'])
        self.assertGreater(len(json.loads(before['user.json'])['password']), 30)

    def test_existing_symlink_or_insecure_file_rejected(self):
        self.module.initialize(self.root, 'admin@example.org', 'reader@example.org', 'Reader')
        p = self.root / 'api-key'
        p.chmod(0o644)
        with self.assertRaises(self.module.CheckError):
            self.module.initialize(self.root, 'admin@example.org', 'reader@example.org', 'Reader')
        p.unlink()
        p.symlink_to(self.root / 'webui-key')
        with self.assertRaises(self.module.CheckError):
            self.module.initialize(self.root, 'admin@example.org', 'reader@example.org', 'Reader')

    def test_identity_change_requires_explicit_reset(self):
        self.module.initialize(self.root, 'admin@example.org', 'reader@example.org', 'Reader')
        with self.assertRaises(self.module.CheckError):
            self.module.initialize(self.root, 'admin@example.org', 'other@example.org', 'Reader')

    def test_bootstrap_creates_user_only_after_missing_login(self):
        self.module.initialize(self.root, 'admin@example.org', 'reader@example.org', 'Reader')
        client = Mock()
        client.request.side_effect = [
            {'token': 'admin-token', 'role': 'admin'},
            self.module.CheckError('endpoint returned HTTP 400'),
            {'role': 'user', 'email': 'reader@example.org'},
            {'token': 'user-token', 'role': 'user'},
        ]
        self.module.bootstrap(self.root, client, 'http://127.0.0.1:8080')
        calls = client.request.call_args_list
        self.assertEqual(calls[2].args[1], '/api/v1/auths/add')
        self.assertEqual(calls[2].args[2]['role'], 'user')
        self.assertEqual(calls[2].kwargs['token'], 'admin-token')

    def test_existing_user_is_not_recreated(self):
        self.module.initialize(self.root, 'admin@example.org', 'reader@example.org', 'Reader')
        client = Mock()
        client.request.side_effect = [{'token': 'admin-token', 'role': 'admin'}, {'token': 'user-token', 'role': 'user'}]
        self.module.bootstrap(self.root, client, 'http://127.0.0.1:8080')
        self.assertEqual(client.request.call_count, 2)

    def test_network_error_does_not_create_account(self):
        self.module.initialize(self.root, 'admin@example.org', 'reader@example.org', 'Reader')
        client = Mock()
        client.request.side_effect = [{'token': 'admin-token', 'role': 'admin'}, self.module.CheckError('endpoint unreachable')]
        with self.assertRaises(self.module.CheckError):
            self.module.bootstrap(self.root, client, 'http://127.0.0.1:8080')
        self.assertEqual(client.request.call_count, 2)


if __name__ == '__main__':
    unittest.main()
