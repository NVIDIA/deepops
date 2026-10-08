"""Test secrets and the pinned Open WebUI account/model-access API contract."""
import importlib.util
import json
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts/validation'))
from validate_playground import CheckError, login


class WebUIContract:
    """Stateful boundary fixture from Open WebUI v0.11.4 auths/models routes.

    A non-admin cannot see an unregistered model. The admin access-update
    route upserts a base-model row and replaces its grants.
    """
    def __init__(self, user_exists=False):
        self.user_exists = user_exists
        self.models = {}
        self.calls = []
        self.identity = {'id': 'reader-id', 'email': 'reader@example.org', 'role': 'user'}
        self.grant_error = False
        self.ignore_grant = False
        self.ignore_tool_policy = False
        self.response_changes = {}
        self.policy_response_changes = {}

    def request(self, base, path, payload=None, token=None):
        self.calls.append((path, payload, token))
        if path == '/api/v1/auths/signin':
            if payload['email'] == 'admin@example.org':
                return {'token': 'admin-token', 'role': 'admin'}
            if not self.user_exists:
                raise CheckError('endpoint returned HTTP 400')
            return {'token': 'user-token', 'role': 'user'}
        if path == '/api/v1/auths/add' and token == 'admin-token':
            if self.user_exists or payload['role'] != 'user':
                raise AssertionError('duplicate account or incorrect role')
            self.user_exists = True
            return dict(self.identity)
        if path == '/api/v1/auths/' and token == 'user-token':
            return dict(self.identity)
        if path == '/api/v1/models/model/access/update' and token == 'admin-token':
            if self.grant_error:
                raise CheckError('endpoint returned HTTP 403')
            model = self.models.get(payload['id']) or {
                'id': payload['id'], 'user_id': 'admin-id', 'base_model_id': None,
                'name': payload['id'], 'params': {}, 'meta': {}, 'is_active': True,
                'created_at': 1, 'updated_at': 1, 'access_grants': []}
            if not self.ignore_grant:
                model['access_grants'] = [dict(g, id='grant-id', resource_type='model',
                                               resource_id=payload['id'], created_at=1)
                                          for g in payload['access_grants']]
            model.update(self.response_changes)
            self.models[payload['id']] = model
            return model
        if path == '/api/v1/models/model/update' and token == 'admin-token':
            model = self.models[payload['id']]
            if not self.ignore_tool_policy:
                model.update(payload)
            model.update(self.policy_response_changes)
            return model
        if path == '/api/models' and token == 'user-token':
            return {'data': [m for m in self.models.values() if any(
                g['principal_type'] == 'user' and g['principal_id'] == 'reader-id'
                and g['permission'] == 'read' for g in m['access_grants'])]}
        raise AssertionError('unexpected route or wrong account token: ' + path)


class AccountTests(unittest.TestCase):
    def setUp(self):
        path = ROOT / 'roles/model_playground/files/playground_accounts.py'
        spec = importlib.util.spec_from_file_location('playground_accounts', path)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'secrets'

    def initialize(self):
        self.module.initialize(self.root, 'admin@example.org', 'reader@example.org', 'Reader')

    def test_secrets_private_and_stable_on_rerun(self):
        self.initialize()
        before = {p.name: p.read_bytes() for p in self.root.iterdir()}
        self.initialize()
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.root.iterdir()})
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o700)
        for p in self.root.iterdir():
            self.assertEqual(stat.S_IMODE(p.stat().st_mode), 0o600)
        self.assertNotEqual(json.loads(before['admin.json'])['password'], json.loads(before['user.json'])['password'])
        self.assertGreater(len(json.loads(before['user.json'])['password']), 30)

    def test_existing_symlink_or_insecure_file_rejected(self):
        self.initialize()
        p = self.root / 'api-key'
        p.chmod(0o644)
        with self.assertRaises(self.module.CheckError):
            self.initialize()
        p.unlink()
        p.symlink_to(self.root / 'webui-key')
        with self.assertRaises(self.module.CheckError):
            self.initialize()

    def test_identity_change_requires_explicit_reset(self):
        self.initialize()
        with self.assertRaises(self.module.CheckError):
            self.module.initialize(self.root, 'admin@example.org', 'other@example.org', 'Reader')

    def test_bootstrap_registers_model_and_grants_only_named_user_read(self):
        self.initialize()
        for existing in [False, True]:
            with self.subTest(existing=existing):
                client = WebUIContract(user_exists=existing)
                base = 'http://127.0.0.1:8080'
                self.assertEqual(client.request(base, '/api/models', token='user-token')['data'], [])
                self.module.bootstrap(self.root, client, base, 'local-chat')
                token = login(client, base, json.loads((self.root / 'user.json').read_text()), 'user')
                self.assertEqual([m['id'] for m in client.request(base, '/api/models', token=token)['data']], ['local-chat'])
                creates = [c for c in client.calls if c[0] == '/api/v1/auths/add']
                self.assertEqual(len(creates), 0 if existing else 1)
                grants = [c for c in client.calls if c[0] == '/api/v1/models/model/access/update']
                self.assertEqual(grants, [('/api/v1/models/model/access/update', {
                    'id': 'local-chat', 'access_grants': [
                        {'principal_type': 'user', 'principal_id': 'reader-id', 'permission': 'read'}]}, 'admin-token')])

    def test_bootstrap_disables_builtin_tools_and_repairs_policy_on_rerun(self):
        self.initialize()
        client = WebUIContract(user_exists=True)
        base = 'http://127.0.0.1:8080'
        for _ in range(2):
            self.module.bootstrap(self.root, client, base, 'local-chat')
            model = client.models['local-chat']
            capabilities = model['meta'].get('capabilities', {})
            for name in ['builtin_tools', 'code_interpreter', 'web_search', 'image_generation', 'terminal']:
                self.assertIs(capabilities.get(name), False, name)
            self.assertEqual(model['meta']['toolIds'], [])
            self.assertEqual(model['meta']['filterIds'], [])
            self.assertEqual(model['params'], {})
            self.assertEqual(len(model['access_grants']), 1)
            self.assertEqual(model['access_grants'][0]['permission'], 'read')
            model['meta'] = {'capabilities': {'builtin_tools': True}, 'toolIds': ['unexpected']}

    def test_unacknowledged_tool_policy_fails_bootstrap(self):
        self.initialize()
        client = WebUIContract(user_exists=True)
        client.ignore_tool_policy = True
        with self.assertRaises(self.module.CheckError):
            self.module.bootstrap(self.root, client, 'http://127.0.0.1:8080', 'local-chat')

    def test_policy_update_cannot_drop_grants_or_change_model_identity(self):
        self.initialize()
        for change in [{'id': 'other-model'}, {'base_model_id': 'remote'}, {'is_active': False},
                       {'access_grants': []}, {'meta': None}, {'params': {'function_calling': 'legacy'}}]:
            with self.subTest(change=change):
                client = WebUIContract(user_exists=True)
                client.policy_response_changes = change
                with self.assertRaises(self.module.CheckError):
                    self.module.bootstrap(self.root, client, 'http://127.0.0.1:8080', 'local-chat')

    def test_rerun_repairs_missing_grant_without_recreating_user(self):
        self.initialize()
        client = WebUIContract(user_exists=True)
        base = 'http://127.0.0.1:8080'
        self.module.bootstrap(self.root, client, base, 'local-chat')
        client.models['local-chat']['access_grants'] = []
        self.module.bootstrap(self.root, client, base, 'local-chat')
        self.assertEqual(len(client.request(base, '/api/models', token='user-token')['data']), 1)
        self.assertFalse(any(c[0] == '/api/v1/auths/add' for c in client.calls))

    def test_invalid_user_identity_never_grants_access(self):
        self.initialize()
        for change in [{'id': '*'}, {'id': ''}, {'id': None}, {'role': 'admin'}, {'email': 'other@example.org'}]:
            with self.subTest(change=change):
                client = WebUIContract(user_exists=True)
                client.identity.update(change)
                with self.assertRaises(self.module.CheckError):
                    self.module.bootstrap(self.root, client, 'http://127.0.0.1:8080', 'local-chat')
                self.assertEqual(client.models, {})

    def test_failed_or_unacknowledged_grant_fails_bootstrap(self):
        self.initialize()
        for failure in ['grant_error', 'ignore_grant']:
            with self.subTest(failure=failure):
                client = WebUIContract(user_exists=True)
                setattr(client, failure, True)
                with self.assertRaises(self.module.CheckError):
                    self.module.bootstrap(self.root, client, 'http://127.0.0.1:8080', 'local-chat')

    def test_wrong_model_or_overbroad_acknowledgment_fails_bootstrap(self):
        self.initialize()
        grant = {'principal_type': 'user', 'principal_id': 'reader-id', 'permission': 'read'}
        for change in [{'id': 'other-model'}, {'base_model_id': 'remote-model'}, {'is_active': False},
                       {'access_grants': [dict(grant, permission='write')]},
                       {'access_grants': [dict(grant, principal_id='*')]},
                       {'access_grants': [grant, dict(grant, principal_id='other-id')]}]:
            with self.subTest(change=change):
                client = WebUIContract(user_exists=True)
                client.response_changes = change
                with self.assertRaises(self.module.CheckError):
                    self.module.bootstrap(self.root, client, 'http://127.0.0.1:8080', 'local-chat')

    def test_missing_or_unsafe_model_rejected_before_requests(self):
        client = WebUIContract()
        for model in [None, '', 'bad model', '../model']:
            with self.subTest(model=model), self.assertRaises(self.module.CheckError):
                self.module.bootstrap(self.root, client, 'http://127.0.0.1:8080', model)
        self.assertEqual(client.calls, [])

    def test_network_error_does_not_create_account(self):
        self.initialize()
        client = Mock()
        client.request.side_effect = [{'token': 'admin-token', 'role': 'admin'}, self.module.CheckError('endpoint unreachable')]
        with self.assertRaises(self.module.CheckError):
            self.module.bootstrap(self.root, client, 'http://127.0.0.1:8080', 'local-chat')
        self.assertEqual(client.request.call_count, 2)


if __name__ == '__main__':
    unittest.main()
