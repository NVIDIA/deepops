# Slurm log search (optional)

DeepOps can run Loki (log store) on the monitoring node and Grafana Alloy (collector) on every node, so you can search system, kernel and Slurm daemon logs in Grafana. It is **off by default**; the existing rsyslog forwarding to the head node is unchanged.

## Enable

In `config/group_vars/slurm-cluster.yml`:

```yaml
slurm_enable_monitoring: true
slurm_enable_log_search: true
# loki_retention_period: 168h   # default 7 days; must be a multiple of 24h
```

Then run `ansible-playbook -l slurm-cluster playbooks/slurm-cluster.yml`, or just the pieces:

```bash
ansible-playbook playbooks/slurm-cluster/loki.yml -e hostlist=slurm-master
ansible-playbook playbooks/slurm-cluster/alloy.yml -e hostlist=slurm-cluster
ansible-playbook playbooks/slurm-cluster/grafana.yml -e hostlist=slurm-master -e grafana_enable_loki=true
```

## Use

Grafana (`http://<monitoring node>:3000/`) gets a **Loki** data source and a **Cluster logs** dashboard (log volume by host, journal/kernel, Slurm daemons, GPU XID and out-of-memory kernel messages). To follow one job, search for its job ID in the *Search text* box.

Labels: `host`, `job` (`systemd-journal` or `slurm`), `unit`, `level`, `transport` (`kernel` for kernel messages).

## Notes

- Loki listens on port 3100 with no authentication. Keep it on the cluster network (see `docs/misc/firewall.md`).
- Alloy reads Slurm logs from `/var/log/slurm/*.log`; change `alloy_slurm_log_paths` if your logs live elsewhere.
- Disable by setting the flag back to `false` and running `systemctl disable --now docker.loki.service docker.alloy.service` on the nodes; Grafana drops the Loki data source on its next run. The `deepops_loki_data` Docker volume keeps old logs until you remove it.
