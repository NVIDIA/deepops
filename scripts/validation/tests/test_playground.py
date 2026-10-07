"""Offline end-to-end contract, using HTTP servers instead of GPU services."""
import contextlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'validate_playground.py'
REVISION = 'b' * 40
SNAPSHOT = '/models/models--example--chat/snapshots/' + REVISION


@contextlib.contextmanager
def endpoint(mode='good'):
    requests = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            self.respond()

        def do_POST(self):
            self.respond()

        def respond(self):
            body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
            payload = json.loads(body) if body else None
            requests.append((self.path, payload, self.headers.get('Authorization')))
            status = 200
            models = [{'id': 'local-chat', 'root': SNAPSHOT, 'owned_by': 'vllm'}]
            if mode == 'wrong-root':
                models[0]['root'] = '/models/unpinned'
            if mode == 'extra-backend' and self.path == '/v1/models':
                models.append({'id': 'cloud-model', 'root': 'remote'})
            if self.path == '/api/v1/auths/signin':
                value = {'token': 'test-session', 'role': 'user'}
                if payload != {'email': 'reader@example.org', 'password': 'test-password'}:
                    status = 401
                if mode == 'admin':
                    value['role'] = 'admin'
                if mode == 'bad-token':
                    value['token'] = ''
            elif self.path == '/v1/models':
                value = {'data': models}
                if self.headers.get('Authorization') != 'Bearer test-key':
                    status = 401
            elif self.path == '/api/models':
                value = {'data': models}
                if mode == 'cloud':
                    value = {'data': [{'id': 'cloud-model'}]}
                if mode == 'extra-ui':
                    value['data'].append({'id': 'cloud-model'})
                if self.headers.get('Authorization') != 'Bearer test-session':
                    status = 401
            elif self.path == '/api/chat/completions':
                value = {'model': 'local-chat', 'choices': [{'message': {'role': 'assistant', 'content': 'A small reply'}}]}
                if not payload or payload.get('model') != 'local-chat' or payload.get('stream') is not False:
                    status = 400
                if mode == 'empty':
                    value['choices'][0]['message']['content'] = '  '
                if mode == 'reasoning-only':
                    value['choices'][0]['message'] = {'reasoning_content': 'thinking'}
                if mode == 'wrong-reply-model':
                    value['model'] = 'cloud-model'
                if self.headers.get('Authorization') != 'Bearer test-session':
                    status = 401
            else:
                value = {'status': 'ok'}
            if mode == 'health-only' and self.path != '/health':
                status, value = 404, {'error': 'health only'}
            if mode == 'redirect':
                self.send_response(302)
                self.send_header('Location', '/health')
                self.end_headers()
                return
            if mode == 'echo-error':
                status, value = 500, {'error': 'test-password test-key test-session'}
            data = (b'x' * (1024 * 1024 + 1) if mode == 'oversized' else
                    b'not-json' if mode == 'malformed' else json.dumps(value).encode())
            self.send_response(status)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.01})
    thread.start()
    try:
        yield 'http://127.0.0.1:' + str(server.server_port), requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class PlaygroundTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.user = Path(self.tmp.name) / 'user.json'
        self.user.write_text(json.dumps({'email': 'reader@example.org', 'password': 'test-password'}))
        self.user.chmod(0o600)
        self.key = Path(self.tmp.name) / 'api-key'
        self.key.write_text('test-key')
        self.key.chmod(0o600)

    def run_check(self, url, *extra):
        run = subprocess.run([sys.executable, str(SCRIPT), '--json', '--webui-url', url,
                              '--vllm-url', url, '--model', 'local-chat',
                              '--repo-id', 'example/chat', '--revision', REVISION,
                              '--user-file', str(self.user), '--api-key-file', str(self.key),
                              *extra], capture_output=True, text=True, timeout=8)
        self.assertEqual(run.stderr, '', run.stderr)
        self.assertIn(run.returncode, (0, 1))
        result = json.loads(run.stdout)
        self.assertEqual(result['ok'], run.returncode == 0)
        for secret in ['test-key', 'test-password', 'test-session', 'A small reply']:
            self.assertNotIn(secret, run.stdout)
        return result

    def test_chat_and_exact_model_identity_required(self):
        with endpoint() as (url, requests):
            result = self.run_check(url)
        self.assertTrue(result['ok'], result)
        self.assertEqual(result['checks'], {'login': True, 'backend_model': True,
                                          'ui_model': True, 'chat': True})
        self.assertEqual([r[0] for r in requests], ['/api/v1/auths/signin', '/v1/models',
                                                  '/api/models', '/api/chat/completions'])

    def test_ui_model_and_chat_use_the_ordinary_user_session(self):
        with endpoint() as (url, requests):
            result = self.run_check(url)
        self.assertTrue(result['checks']['ui_model'])
        self.assertTrue(result['checks']['chat'])
        signins = [r for r in requests if r[0] == '/api/v1/auths/signin']
        self.assertEqual(len(signins), 1)
        self.assertEqual(signins[0][1]['email'], 'reader@example.org')
        for path in ['/api/models', '/api/chat/completions']:
            calls = [r for r in requests if r[0] == path]
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0][2], 'Bearer test-session')
        # An admin login must fail before either user-level check can run.
        with endpoint('admin') as (url, requests):
            result = self.run_check(url)
        self.assertFalse(result['ok'])
        self.assertFalse(result['checks']['ui_model'])
        self.assertFalse(result['checks']['chat'])
        self.assertEqual([r[0] for r in requests], ['/api/v1/auths/signin'])

    def test_negative_controls_fail_closed(self):
        for mode in ['cloud', 'extra-ui', 'extra-backend', 'wrong-root', 'empty', 'reasoning-only',
                     'wrong-reply-model', 'health-only', 'admin', 'bad-token', 'malformed',
                     'redirect', 'echo-error', 'oversized']:
            with self.subTest(mode=mode), endpoint(mode) as (url, _):
                self.assertFalse(self.run_check(url)['ok'])

    def test_insecure_secrets_rejected_before_http(self):
        self.user.chmod(0o644)
        with endpoint() as (url, requests):
            self.assertFalse(self.run_check(url)['ok'])
        self.assertEqual(requests, [])

    def test_unpinned_revision_rejected_before_http(self):
        with endpoint() as (url, requests):
            self.assertFalse(self.run_check(url, '--revision', 'main')['ok'])
        self.assertEqual(requests, [])

    def test_proxy_environment_ignored(self):
        with endpoint() as (url, _):
            old = dict(os.environ)
            try:
                os.environ.update(http_proxy='http://127.0.0.1:1', HTTP_PROXY='http://127.0.0.1:1', no_proxy='', NO_PROXY='')
                self.assertTrue(self.run_check(url)['ok'])
            finally:
                os.environ.clear()
                os.environ.update(old)


if __name__ == '__main__':
    unittest.main()
