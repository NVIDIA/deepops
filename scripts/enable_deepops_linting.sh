#!/bin/bash

echo "Enabling pre-commit hooks to lint Ansible, Shell, and Python"
cp -v .githooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
