#!/bin/bash
set -ex

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

CENTOS_MIRRIR_URL="${CENTOS_MIRROR_URL:-http://mirrors.ocf.berkeley.edu/centos/7.6.1810/isos/x86_64/}"
CENTOS_ISO="${CENTOS_ISO:-CentOS-7-x86_64-Minimal-1810.iso}"

SYNC_YUM_CONF="${SYNC_YUM_CONF:-${SCRIPT_DIR}/yum.conf}"
SYNC_DEST_DIR="${SYNC_DEST_DIR:-/tmp/deepops/yum_mirror}"
# TODO: fix download of libnvidia-container,nvidia-container-runtime,nvidia-docker
REPOLIST="${REPOLIST:-base,updates,extras,centosplus,cuda,docker-ce-stable,docker-engine,epel}"
SYNC_DRY_RUN="${SYNC_DRY_RUN:-}"

if ! which wget; then
	echo "Need wget tool to download ISOs"
	exit 1
fi

if ! which reposync; then
	echo "reposync tool not found in PATH but needed to mirror repos."
	echo "On CentOS and Ubuntu this is provided by the yum-utils package."
	exit 1
fi

echo "Downloading the installation ISO for convenience"
if [ "${SYNC_DRY_RUN}" ]; then
	echo "DRY RUN: would have attempted download of ${CENTOS_MIRROR_URL}/${CENTOS_ISO}"
else
	wget -c -O "${SYNC_DEST_DIR}/${CENTOS_ISO}" "${CENTOS_MIRROR_URL}/${CENTOS_ISO}"
fi

if [ "${SYNC_DRY_RUN}" ]; then
	echo "DRY RUN: printing URLs to download for reposync"
	sleep 3
	reposync -c "${SYNC_YUM_CONF}" -r "${REPOLIST}" -p "${SYNC_DEST_DIR}" -u
else
	reposync -c "${SYNC_YUM_CONF}" -r "${REPOLIST}" -p "${SYNC_DEST_DIR}"
fi
