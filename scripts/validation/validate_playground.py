#!/usr/bin/env python3
"""Prove a named user's chat traverses Open WebUI to exactly one pinned local model."""
import argparse
import http.client
import ipaddress
import json
import math
import os
import re
import ssl
import stat
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


class CheckError(Exception):
    """Safe failure text: never include remote responses or credentials."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise CheckError('redirects are not allowed')


def read_secret(path):
    """Read only a private regular file owned by the executing account."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'r') as stream:
            info = os.fstat(stream.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid()
                    or info.st_mode & 0o077 or info.st_size > 16384):
                raise CheckError('secret files must be owner-only regular files owned by this account')
            value = stream.read(16385).strip()
            if not value:
                raise CheckError('secret file is empty')
            return value
    except (OSError, UnicodeError):
        raise CheckError('secret file could not be read safely') from None


def origin(value):
    try:
        p = urllib.parse.urlsplit(value)
        if (p.scheme not in ('http', 'https') or not p.hostname or '@' in p.netloc
                or p.path not in ('', '/') or p.query or p.fragment or not p.port):
            raise ValueError
        if p.scheme == 'http' and p.hostname not in ('vllm', 'webui'):
            if not ipaddress.ip_address(p.hostname).is_loopback:
                raise ValueError
        return p.scheme + '://' + p.netloc
    except ValueError:
        raise CheckError('use an explicit HTTPS origin and port, or HTTP loopback/private service name') from None


class Client:
    def __init__(self, timeout=120, ca_file=None):
        if not math.isfinite(timeout) or not 0 < timeout <= 120:
            raise CheckError('timeout must be positive and at most 120 seconds')
        self.timeout = timeout
        try:
            context = ssl.create_default_context(cafile=ca_file)
        except (OSError, ssl.SSLError):
            raise CheckError('CA certificate could not be loaded') from None
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect(),
                                                  urllib.request.HTTPSHandler(context=context))

    def request(self, base, path, payload=None, token=None):
        data = None if payload is None else json.dumps(payload).encode()
        headers = {'Content-Type': 'application/json', 'Accept': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        req = urllib.request.Request(base + path, data=data, headers=headers)
        try:
            deadline = time.monotonic() + self.timeout
            with self.opener.open(req, timeout=self.timeout) as response:
                if response.status != 200:
                    raise CheckError('endpoint did not return HTTP 200')
                body = bytearray()
                while True:
                    if time.monotonic() >= deadline:
                        raise CheckError('response time limit exceeded')
                    chunk = response.read1(min(65536, 1024 * 1024 + 1 - len(body)))
                    body.extend(chunk)
                    if len(body) > 1024 * 1024:
                        raise CheckError('response exceeds 1 MiB')
                    if not chunk:
                        break
            return json.loads(body)
        except urllib.error.HTTPError as exc:
            status = exc.code
            exc.close()
            raise CheckError('endpoint returned HTTP ' + str(status)) from None
        except (OSError, urllib.error.URLError, http.client.HTTPException):
            raise CheckError('endpoint unreachable, timed out, or TLS verification failed') from None
        except (ValueError, UnicodeError, RecursionError):
            raise CheckError('endpoint returned invalid JSON') from None


def login(client, base, credentials, role):
    if not isinstance(credentials, dict) or not all(isinstance(credentials.get(k), str) and credentials[k]
                                                   for k in ('email', 'password')):
        raise CheckError('credentials require email and password')
    result = client.request(base, '/api/v1/auths/signin',
                            {k: credentials[k] for k in ('email', 'password')})
    if (not isinstance(result, dict) or result.get('role') != role
            or not isinstance(result.get('token'), str) or not result['token']
            or any(c.isspace() for c in result['token'])):
        raise CheckError('login did not yield the required account role and session')
    return result['token']


def only_model(value, model, snapshot=None):
    if (not isinstance(value, dict) or not isinstance(value.get('data'), list)
            or len(value['data']) != 1 or not isinstance(value['data'][0], dict)
            or value['data'][0].get('id') != model):
        raise CheckError('model list must contain exactly the expected local model')
    if snapshot is not None and value['data'][0].get('root') != snapshot:
        raise CheckError('backend model root is not the pinned snapshot path')


def validate(args):
    result = {'schema_version': 1, 'ok': False,
              'checks': dict.fromkeys(('login', 'backend_model', 'ui_model', 'chat'), False), 'errors': []}
    stage = 'arguments'
    try:
        ui, backend = origin(args.webui_url), origin(args.vllm_url)
        if (not re.fullmatch(r'[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+', args.repo_id)
                or '..' in args.repo_id or not re.fullmatch(r'[0-9a-f]{40}', args.revision)
                or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}', args.model)):
            raise CheckError('model identity requires a safe served name, repository and full revision')
        snapshot = '/models/models--' + args.repo_id.replace('/', '--') + '/snapshots/' + args.revision
        client = Client(args.timeout, args.ca_file)
        credentials = json.loads(read_secret(args.user_file))
        key = read_secret(args.api_key_file)
        if any(c.isspace() for c in key):
            raise CheckError('invalid API key file')
        stage = 'login'
        token = login(client, ui, credentials, 'user')
        result['checks'][stage] = True
        stage = 'backend_model'
        only_model(client.request(backend, '/v1/models', token=key), args.model, snapshot)
        result['checks'][stage] = True
        stage = 'ui_model'
        only_model(client.request(ui, '/api/models', token=token), args.model)
        result['checks'][stage] = True
        stage = 'chat'
        reply = client.request(ui, '/api/chat/completions', {
            'model': args.model, 'messages': [{'role': 'user', 'content': 'Say hello in one short sentence. /no_think'}],
            'max_tokens': 256, 'temperature': 0, 'stream': False,
            # v0.11.4 uses session_id to select the browser's builtin-tool
            # middleware. Omit chat_id so the reply remains synchronous and
            # no stored chat/background task is created. Do not force legacy
            # calling or tool_choice=none: that would mask a broken UI policy.
            'session_id': 'playground-validator', 'features': {}, 'tool_servers': [],
        }, token=token)
        if not isinstance(reply, dict) or reply.get('error') or reply.get('model') != args.model:
            raise CheckError('chat reply must identify the expected local model')
        choices = reply.get('choices')
        message = choices[0].get('message') if isinstance(choices, list) and choices and isinstance(choices[0], dict) else None
        if (not isinstance(message, dict) or message.get('error') or message.get('tool_calls')
                or not isinstance(message.get('content'), str) or not message['content'].strip()):
            raise CheckError('chat reply must contain nonempty assistant content')
        result['checks'][stage] = True
        result['ok'] = True
    except CheckError as exc:
        result['errors'].append({'stage': stage, 'message': str(exc)})
    except (ValueError, TypeError, RecursionError):
        result['errors'].append({'stage': stage, 'message': 'invalid input or response structure'})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument('--webui-url', default='http://127.0.0.1:8080')
    parser.add_argument('--vllm-url', default='http://vllm:8000')
    parser.add_argument('--model', required=True)
    parser.add_argument('--repo-id', required=True)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--user-file', required=True, help='Owner-only JSON with email and password')
    parser.add_argument('--api-key-file', required=True)
    parser.add_argument('--ca-file', help='CA for HTTPS; TLS verification is never disabled')
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    result = validate(args)
    print(json.dumps(result, sort_keys=True) if args.json else
          'PASS: authenticated local chat verified' if result['ok'] else 'FAIL: playground validation failed')
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
