#!/bin/bash
set -ex

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SYNC_YUM_CONF="${SYNC_YUM_CONF:-${SCRIPT_DIR}/yum.conf}"
SYNC_DEST_DIR="/tmp/deepops/yum_mirror"
REPOLIST="base,updates,extras,centosplus,cuda,docker-ce-stable,docker-engine,epel"
SYNC_DRY_RUN="${SYNC_DRY_RUN:-}"

if ! which reposync; then
	echo "reposync tool not found in PATH but needed to mirror repos."
	echo "On CentOS and Ubuntu this is provided by the yum-utils package."
	exit 1
fi

if [ "${SYNC_DRY_RUN}" ]; then
	reposync -c "${SYNC_YUM_CONF}" -r "${REPOLIST}" -p "${SYNC_DEST_DIR}" -u
else
	reposync -c "${SYNC_YUM_CONF}" -r "${REPOLIST}" -p "${SYNC_DEST_DIR}" -u
fi
