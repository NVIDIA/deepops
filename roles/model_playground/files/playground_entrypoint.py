#!/usr/bin/env python3
"""Load host-generated private files at container startup, not into Docker metadata."""
import json
import os
from pathlib import Path
import sys

from validate_playground import CheckError, read_secret


def launch(service, args, directory=Path('/run/playground')):
    directory = Path(directory)
    key = read_secret(directory / 'api-key')
    if service == 'vllm':
        os.execvp('python3', ['python3', '-m', 'vllm.entrypoints.openai.api_server',
                              *args, '--api-key', key])
    elif service == 'webui':
        admin = json.loads(read_secret(directory / 'admin.json'))
        os.environ.update(OPENAI_API_KEYS=key,
                          WEBUI_SECRET_KEY=read_secret(directory / 'webui-key'),
                          WEBUI_ADMIN_EMAIL=admin['email'], WEBUI_ADMIN_PASSWORD=admin['password'])
        os.execvp('bash', ['bash', '/app/backend/start.sh'])
    else:
        raise CheckError('unknown service')


if __name__ == '__main__':
    try:
        launch(sys.argv[1], sys.argv[2:])
    except (CheckError, OSError, ValueError, KeyError, IndexError):
        sys.exit('Private service initialization failed')
