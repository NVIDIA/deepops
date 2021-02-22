#!/bin/bash
source workloads/jenkins/scripts/jenkins-common.sh

# Assuming that we have rsyslog forwarding configured, we should be able to
# generate a known syslog message on the GPU node and observe it in the logs
# on the management node

set -ex

RSYSLOG_TAG="deepops_jenkins_slurm"
RSYSLOG_MESSAGE="test message"

# Generate syslog message on GPU node
ssh \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.6${GPU01}" \
	"logger -t ${RSYSLOG_TAG} ${RSYSLOG_MESSAGE}"

# Sleep for a couple seconds just in case forwarding is slow
sleep 2

# Check for syslog message on the login node
ssh \
	-o "StrictHostKeyChecking no" \
	-o "UserKnownHostsFile /dev/null" \
	-l vagrant \
	-i "${HOME}/.ssh/id_rsa" \
	"10.0.0.5${GPU01}" \
	"sudo grep -R -E '.*virtual-gpu.*${RSYSLOG_TAG}' /var/log/deepops-hosts/ | grep -v mgmt"
