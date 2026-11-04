# GPU Nodes dashboard checks

Run without a cluster using Python 3 and Prometheus's `promtool`:

```sh
python3 -m unittest discover -s tests/monitoring -v
# If promtool is not on PATH:
PROMTOOL=/path/to/promtool python3 -m unittest discover -s tests/monitoring -v
```

The checks load `src/dashboards/gpu-dashboard.json`, check every exporter
selector, and execute the variable queries and all panel expressions using
`promtool test rules`. Fixtures cover Kubernetes exporters at different IPs
(and non-default ports), Slurm hostname inventories with short OS hostnames,
and Slurm IP inventories. An unrelated node checks selection isolation.
No metrics server, Grafana instance, GPU, or cluster is needed.

On Kubernetes, the visible server variable uses the `kubernetes_node` label
provided by DeepOps's GPU scrape configuration. Hidden dependent variables
resolve GPU and node-exporter instances independently; node-exporter identity
comes from `node_uname_info.nodename`. On Slurm, GPU metrics without that label
keep the inventory-address fallback and default exporter ports.

These are static/query checks, not live Grafana confirmation. Existing Grafana
imports or Kubernetes dashboard ConfigMaps must be updated to use the new JSON;
the monitoring install script does not replace an existing dashboard ConfigMap.
