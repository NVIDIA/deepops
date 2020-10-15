#!/bin/bash

FAILED=0
if ! which ansible-lint; then
	echo "ansible-lint not found in PATH"
	FAILED=1
fi
if ! which shellcheck; then
	echo "shellcheck not found in PATH"
	FAILED=1
fi
if ! which pylint; then
	echo "pylint not found in PATH"
	FAILED=1
fi
if [ ${FAILED} -ne 0 ]; then
	echo
	echo 'One or more required linters not found!'
	echo 'Please install the missing linter using pip or your system package manager,'
	echo 'and try again.'
	echo
	echo 'Pre-commit hook not enabled.'
	exit 1
fi

echo "Enabling pre-commit hooks to lint Ansible, Shell, and Python"
cp -v src/repo/githooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
