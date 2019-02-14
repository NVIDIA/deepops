[Ansible Guide](https://www.ansible.com/overview/how-ansible-works)
===

Ansible is an automation tool that simplifies configuration of computers.

Install Ansible on any system which can access target nodes via SSH. This can be a laptop,
small virtual machine, or cluster management server.

## Ansible Setup

### Requirements

  * Control machine with supported OS to run Ansible
  * [Passwordless](docs/ANSIBLE.md#passwordless-configuration-using-ssh-keys) (SSH key) access from Ansible system to Universal GPU servers

A script is provided to install Ansible on Ubuntu and RHEL/CentOS machines. Ansible can
also be installed on Mac OS and Windows (WSL).

```sh
# Installation script for Ubuntu/RHEL
./scripts/install_ansible.sh

# Install required Ansible roles
ansible-galaxy install -r requirements.yml
```

See the [Ansible documentation](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
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

[Ansible playbooks](https://docs.ansible.com/ansible/latest/user_guide/playbooks.html) are file which
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

_Configure Servers_

```sh
# If sudo requires a password, add the -K flag

# For servers in the `[management]` group
ansible-playbook playbooks/setup-mgmt-servers.yml

# For servers in the `[gpu-servers]` group
ansible-playbook playbooks/setup-gpu-servers.yml
```

### Useful commands

_Debugging_

Show host vars: `ansible all -m debug -a 'var=hostvars'`

## Reference Documentation

Inventory reference: https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html

Variable configuration reference: https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html
