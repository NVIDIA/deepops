Standalone Deployment Guide
===

For bootstrapping cluster nodes which will run neither Kubernetes nor Slurm, follow this guide.

> NOTE: The install process should be run from a separate provisioning system since GPU driver installation may trigger a reboot.

1. Set up your provisioning machine.

   This will install Ansible and other software on the provisioning machine which will be used to deploy all other software to the cluster. For more information on Ansible and why we use it, consult the [Ansible Guide](ANSIBLE.md).

   ```sh
   # Install software prerequisites and copy default configuration
   ./scripts/setup.sh
   ```

2. Edit the server inventory and configuration.

   ```sh
   # Edit inventory
   # Add GPU servers to `gpu-servers` group
   vi config/inventory

   # (optional) Modify `config/group_vars/*.yml` to set configuration parameters
   ```

3. Run the standalone playbook.

   ```sh
   # NOTE: If SSH requires a password, add: `-k`
   # NOTE: If sudo on remote machine requires a password, add: `-K`
   # NOTE: If SSH user is different than current user, add: `-u ubuntu`
   ansible-playbook -l gpu-servers playbooks/standalone.yml
   ```
