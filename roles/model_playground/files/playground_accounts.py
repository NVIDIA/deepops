#!/usr/bin/env python3
"""Private, restart-safe playground credentials and Open WebUI account provisioning."""
import argparse
import json
import os
from pathlib import Path
import secrets
import sys

from validate_playground import CheckError, Client, login, read_secret


def initialize(directory, admin_email, user_email, user_name):
    directory = Path(directory)
    if directory.is_symlink():
        raise CheckError('secret directory must not be a symlink')
    directory.mkdir(mode=0o700, parents=False, exist_ok=True)
    info = directory.stat()
    if info.st_uid != os.geteuid() or info.st_mode & 0o077:
        raise CheckError('secret directory must be owner-only')
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


def bootstrap(directory, client, base):
    directory = Path(directory)
    admin = json.loads(read_secret(directory / 'admin.json'))
    user = json.loads(read_secret(directory / 'user.json'))
    token = login(client, base, admin, 'admin')
    try:
        login(client, base, user, 'user')
        return
    except CheckError as exc:
        # Wrong credentials/missing account only. Never create after network,
        # TLS, malformed-response or role failures. Duplicate email fails closed.
        if str(exc) not in ('endpoint returned HTTP 400', 'endpoint returned HTTP 401'):
            raise
    client.request(base, '/api/v1/auths/add', dict(user, role='user'), token=token)
    login(client, base, user, 'user')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['initialize', 'bootstrap'])
    parser.add_argument('--directory', required=True)
    parser.add_argument('--admin-email')
    parser.add_argument('--user-email')
    parser.add_argument('--user-name')
    args = parser.parse_args()
    try:
        if args.action == 'initialize':
            if not args.admin_email or not args.user_email or not args.user_name or args.admin_email == args.user_email:
                raise CheckError('provide two distinct accounts and a user name')
            initialize(args.directory, args.admin_email, args.user_email, args.user_name)
        else:
            bootstrap(args.directory, Client(timeout=15), 'http://127.0.0.1:8080')
    except (CheckError, OSError, ValueError, TypeError):
        # Do not expose passwords, JWTs, response bodies, or supplied identities.
        print('Account provisioning failed; check private files and service readiness.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
