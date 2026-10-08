#!/usr/bin/env python3
"""Private, restart-safe playground credentials and Open WebUI account provisioning."""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import sys

from validate_playground import CheckError, Client, login, read_secret


def initialize(directory, admin_email, user_email, user_name):
    directory = Path(directory)
    if directory.is_symlink():
        raise CheckError('private directory must not be a symlink')
    directory.mkdir(mode=0o700, parents=False, exist_ok=True)
    info = directory.stat()
    if info.st_uid != os.geteuid() or info.st_mode & 0o077:
        raise CheckError('private directory must be owner-only')
    values = {
        'admin.json': json.dumps({'email': admin_email, 'name': 'Administrator', 'password': secrets.token_urlsafe(36)}),
        'user.json': json.dumps({'email': user_email, 'name': user_name, 'password': secrets.token_urlsafe(36)}),
        'api-key': secrets.token_urlsafe(48),
        'webui-key': secrets.token_urlsafe(48),
    }
    for name, value in values.items():
        path = directory / name
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        except FileExistsError:
            read_secret(path)
        else:
            with os.fdopen(fd, 'w') as stream:
                stream.write(value + '\n')
    for name, email in [('admin.json', admin_email), ('user.json', user_email)]:
        if json.loads(read_secret(directory / name)).get('email') != email:
            raise CheckError('existing account identity differs; cleanup before changing accounts')


def bootstrap(directory, client, base, model):
    if not isinstance(model, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}', model):
        raise CheckError('provide a safe served model name')
    directory = Path(directory)
    admin = json.loads(read_secret(directory / 'admin.json'))
    user = json.loads(read_secret(directory / 'user.json'))
    admin_session = login(client, base, admin, 'admin')
    try:
        user_token = login(client, base, user, 'user')
    except CheckError as exc:
        # Wrong credentials/missing account only. Never create after network,
        # TLS, malformed-response or role failures. Duplicate email fails closed.
        if str(exc) not in ('endpoint returned HTTP 400', 'endpoint returned HTTP 401'):
            raise
        client.request(base, '/api/v1/auths/add', dict(user, role='user'), bearer=admin_session)
        user_token = login(client, base, user, 'user')

    # Resolve the principal from the ordinary user's authenticated session,
    # not from a display name or the administrator's identity.
    identity = client.request(base, '/api/v1/auths/', bearer=user_token)
    if (not isinstance(identity, dict) or identity.get('role') != 'user'
            or not isinstance(identity.get('email'), str)
            or identity['email'].casefold() != user['email'].casefold()
            or not isinstance(identity.get('id'), str)
            or not re.fullmatch(r'[A-Za-z0-9_-]+', identity['id'])):
        raise CheckError('could not resolve the named ordinary user')
    grant = {'principal_type': 'user', 'principal_id': identity['id'], 'permission': 'read'}
    # v0.11.4 upserts a missing base-model record here for admins. Reconcile on
    # EVERY run, including pre-existing accounts and retries after partial setup.
    # Replace grants with only this user: no public/wildcard or write access.
    registered = client.request(base, '/api/v1/models/model/access/update',
                                {'id': model, 'access_grants': [grant]}, bearer=admin_session)
    confirm_model_read_access(registered, model, grant)

    # v0.11.4 injects native builtin tools for browser sessions by default,
    # even when code execution and web search are globally disabled. This
    # playground is chat-only: disable injection rather than enable a parser
    # (and executable tools) in the model server. Reconcile on every rerun.
    meta = {'capabilities': dict.fromkeys(('builtin_tools', 'code_interpreter',
                                           'web_search', 'image_generation', 'terminal'), False),
            'toolIds': [], 'filterIds': [], 'knowledge': []}
    configured = client.request(base, '/api/v1/models/model/update', {
        'id': model, 'base_model_id': None, 'name': model, 'is_active': True,
        'params': {}, 'meta': meta, 'access_grants': [grant],
    }, bearer=admin_session)
    confirm_model_read_access(configured, model, grant)
    actual_meta = configured.get('meta')
    if (configured.get('params') != {} or not isinstance(actual_meta, dict)
            or any(actual_meta.get(k) != v for k, v in meta.items())):
        raise CheckError('chat-only model policy was not confirmed')


def confirm_model_read_access(registered, model, grant):
    if (not isinstance(registered, dict) or registered.get('id') != model
            or registered.get('base_model_id') is not None or registered.get('is_active') is not True
            or not isinstance(registered.get('access_grants'), list)
            or len(registered['access_grants']) != 1
            or not isinstance(registered['access_grants'][0], dict)
            or any(registered['access_grants'][0].get(k) != v for k, v in grant.items())):
        raise CheckError('model read access was not confirmed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['initialize', 'bootstrap'])
    parser.add_argument('--directory', required=True)
    parser.add_argument('--admin-email')
    parser.add_argument('--user-email')
    parser.add_argument('--user-name')
    parser.add_argument('--model', help='Exact local served model name (required for bootstrap)')
    args = parser.parse_args()
    try:
        if args.action == 'initialize':
            if not args.admin_email or not args.user_email or not args.user_name or args.admin_email == args.user_email:
                raise CheckError('provide two distinct accounts and a user name')
            initialize(args.directory, args.admin_email, args.user_email, args.user_name)
        else:
            bootstrap(args.directory, Client(timeout=15), 'http://127.0.0.1:8080', args.model)
    except (CheckError, OSError, ValueError, TypeError):
        # Do not expose passwords, JWTs, response bodies, or supplied identities.
        print('Account provisioning failed; check private files and service readiness.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
