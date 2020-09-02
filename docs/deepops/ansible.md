[Ansible Guide](https://www.ansible.com/overview/how-ansible-works)
===

Ansible is a tool that automates the configuration of systems.

Install Ansible on any system which can access target nodes via SSH. This can be a laptop, small virtual machine, or cluster management server. This system is known in these docs as the provisioning node.

Ansible is:
* Agentless (there’s nothing that needs to be installed on other nodes in the cluster)
* Idempotent (you can run the same playbook or task over and over again without repercussions - and tasks that do not require modification of the target nodes will result in Ansible skipping those tasks)
* Easy to maintain & scale (rather than custom scripts)
* Easy to read & use (via YAML playbooks, roles, and tasks)


## Ansible Setup

### Requirements

* Control machine with supported OS to run Ansible
* [Passwordless](docs/deepops/ansible.md#passwordless-configuration-using-ssh-keys) (SSH key) access from Ansible system to Universal GPU servers

A script is provided to install Ansible on Ubuntu and RHEL/CentOS machines. Ansible can also be installed on Mac OS and Windows (WSL).

```sh
# Install Ansible and required roles from Ansible Galaxy
./scripts/setup.sh
```

See the official [Ansible documentation](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
for more detailed installation information.

### Passwordless configuration using SSH keys

Systems are easier to manage with Ansible if you don't have to type passwords. To configure SSH for passwordless
access using SSH keys. Run the following commands on the control machine where Ansible is installed:

```sh
# Generate an SSH keypair for the current user (hit enter to accept defaults)
ssh-keygen

# Copy the new SSH public key to each system that Ansible will configure
# where <username> is the remote username and <host> is the IP or hostname of the remote system
ssh-copy-id <username>@<host>
```

### Password configuration

To use Ansible without SSH keys, you can add flags to have ansible prompt for a password:

If SSH requires a password, add the `-k` flag

If sudo requires a password, add the `-K` flag

## Ansible Playbooks

[Ansible playbooks](https://docs.ansible.com/ansible/latest/user_guide/playbooks.html) are files which
manage the configuration of remote machines.

### Ansible playbook output

*Green* indicates nothing changed as a result of the task

*Yellow* indicates something changed as a result of the task

*Blue* indicates the task was skipped

*Red* indicates the task failed


For more verbose output, add `-v`, `-vv`, `-vvv`, etc. flags

A successful ansible-playbook run should provide a list of hosts and changes
and indicate no failures, for example:

```console
PLAY RECAP ************************************************************************************************************
localhost                  : ok=1    changed=0    unreachable=0    failed=0
node1                      : ok=401  changed=121  unreachable=0    failed=0
```

## Ansible Usage

_Create server inventory_

```sh
# Copy the default configuration
cp -r config.example config

# Review and edit the inventory file to set IPs/hostnames for servers
cat config/inventory

# Review and edit configuration under config/group_vars/*.yml
cat config/group_vars/all.yml
cat config/group_vars/gpu-servers.yml
```

_Run Commands_

To run arbitrary commands in parallel across nodes in the cluster, you can use ansible and the groups or hosts defined in the inventory file, for example:

```sh
# ansible <host-group> -a hostname
ansible management -a hostname
```

_Run Playbooks_

To run playbooks, use the `ansible-playbook` command:

```sh
# If sudo requires a password, add the -K flag

# ansible-playbook <host-group> playbooks/<playbook>.yml
ansible-playbook -l management,localhost -b playbooks/k8s-cluster.yml
```

### Useful commands

_Debugging_

Show host vars: `ansible all -m debug -a 'var=hostvars'`

## Ansible Troubleshooting

_SSH Connection_

Ansible is configured by default in DeepOps to use SSH multiplexing to speed up connections. If a target system changes and you have a persistent connection (the default length is 30m), you may need to clean up the control socket to prevent connection errors:

```
find ~/.ssh -type s -delete
```

_Fact cache inconsistencies_

By default Ansible caches facts about hosts for 24h to speed up provisioning. If a host's details change in that amount of time, you'll want to flush the fact cache so that Ansible will re-collect information about the host.

Add the `--flush-cache` flag to any `ansible-playbook` run to flush the fact cache and force Ansible to re-learn host information.

## Reference Documentation

Inventory reference: https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html

Variable configuration reference: https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html
