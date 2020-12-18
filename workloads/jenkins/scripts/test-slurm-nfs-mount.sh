#!/bin/bash
set -e

source workloads/jenkins/scripts/jenkins-common.sh

# showmount path is different between centos and ubuntu
if [ "${DEEPOPS_VAGRANT_OS}" == "centos" ]; then
	ssh -v \
		-o "StrictHostKeyChecking no" \
		-o "UserKnownHostsFile /dev/null" \
		-l vagrant \
		-i "${HOME}/.ssh/id_rsa" \
		"10.0.0.5${GPU01}" \
		"/usr/sbin/showmount -e | grep home"
else
	ssh -v \
		-o "StrictHostKeyChecking no" \
		-o "UserKnownHostsFile /dev/null" \
		-l vagrant \
		-i "${HOME}/.ssh/id_rsa" \
		"10.0.0.5${GPU01}" \
		"showmount -e | grep home"
fi


ssh -v \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.6${GPU01}" \
        "mount | grep nfs | grep home"
