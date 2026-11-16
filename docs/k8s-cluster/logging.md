# Logging

Optional log search for Kubernetes uses Loki (single binary on a persistent volume) and Grafana Alloy (one pod per node), shown in the Grafana installed by the monitoring script. It is off by default.

> The previous Elastic/Filebeat/Kibana guide was removed: Elastic archived those Helm charts in 2023.

## Install

Install monitoring first, then logging (needs a default StorageClass):

```bash
./scripts/k8s/deploy_monitoring.sh
./scripts/k8s/deploy_logging.sh
```

This installs Loki and Alloy in the `monitoring` namespace, adds Loki as a Grafana data source, and adds a **Cluster logs** dashboard. Logs from all pods are labelled `namespace`, `pod`, `container` and `host`. Default retention is 7 days and the default volume is 50Gi; edit `config/helm/loki.yml` (copy from `config.example/helm/loki.yml`) before installing to change them.

Check the charts render without touching a cluster: `./scripts/k8s/deploy_logging.sh -t`.

Pinned versions: `HELM_LOKI_CHART_VERSION` (community chart `grafana-community/loki`; Grafana Labs moved it there in 2026) and `HELM_ALLOY_CHART_VERSION`.

## Remove

```bash
./scripts/k8s/deploy_logging.sh -d      # keeps stored logs
./scripts/k8s/deploy_logging.sh -d -D   # also deletes the stored logs
```
