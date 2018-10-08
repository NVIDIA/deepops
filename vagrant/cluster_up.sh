#!/bin/bash
set -x

vagrant up
ansible-playbook -k -l slurm-cluster ansible/playbooks/slurm.yml
