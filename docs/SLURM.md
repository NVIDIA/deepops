Slurm
===

```sh
cp -r config.example config

# Edit inventory and add hosts to `login` and `gpu-servers`/`dgx-servers` host groups
vi config/inventory
```

_Install Slurm_ 

```sh
# NOTE: If SSH requires a password, add: `-k`
# NOTE: If sudo on remote machine requires a password, add: `-K`
# NOTE: If SSH user is different than current user, add: `-e ansible_user=ubuntu`
ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml
```

After Slurm has been installed, use the `root` user to run the Slurm playbook
(`-e ansible_user=root`) since only the root user and users currently running a Slurm job will be allowed
to SSH to nodes.
