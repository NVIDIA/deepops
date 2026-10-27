# Upgrade monitoring from 88.6.5 to 92.14.0

This change is for DeepOps 26.12, not 26.11. The target is
`kube-prometheus-stack` **92.14.0**, Prometheus Operator **v0.94.2**;
the chart requires Kubernetes **1.25 or newer**. Fresh-install and live-upgrade
validation are required before release; offline rendering alone is not proof.

## Security and scheduling changes

Upstream [upgrade notes](https://github.com/prometheus-community/helm-charts/blob/kube-prometheus-stack-92.14.0/charts/kube-prometheus-stack/UPGRADE.md)
cover every intervening major version:

- **89:** Grafana subchart moves to 13.x. Review custom Grafana values against
  [its upgrade guide](https://github.com/grafana-community/helm-charts/tree/main/charts/grafana#to-1300).
- **90:** Control-plane ServiceMonitors use Secret-based authorization and
  ConfigMap-based CA references instead of scraper filesystem paths. The default
  chart creates a **non-expiring** Prometheus service-account token Secret.
  This is the token change previously described as part of the 91/92 crossing.
  The operator's `secretFieldSelector` no longer excludes service-account token
  Secrets. Do not restore that exclusion for credentials requiring reconciliation.
- **91:** Operator v0.94.0 removes wildcard RBAC verbs. 92.14.0 uses v0.94.2.
  The operator still has cluster-wide permissions for reconciliation: monitoring
  objects (read, status updates and finalizers), StatefulSets, ConfigMaps and
  Secrets, services/endpoints/EndpointSlices, namespace/node discovery, events,
  ingresses and StorageClasses. Explicit verbs are not namespace confinement.
- **92:** Chart-owned workloads gain `kubernetes.io/os: linux`. Existing
  control-plane selectors are merged, not replaced. Prometheus, Alertmanager,
  operator and enabled Thanos/webhook workloads restart once. Check that matching
  Linux nodes are schedulable; subcharts retain their own selector defaults.

Both shipped monitoring value files explicitly set:

```yaml
prometheus:
  serviceAccount:
    createTokenSecret: false
  controlPlaneScrapeClass:
    enabled: true
```

In 92.14.0 the upstream scrape class supplies Bearer authentication from
`/var/run/secrets/kubernetes.io/serviceaccount/token`, the pod's projected token
rotated by kubelet. All enabled control-plane ServiceMonitors select that class;
no static token Secret is created and authentication is **not** disabled.
Keep service-account token automount enabled. Live proof must establish that the
operator generates authenticated scrapes and rotation does not break them.

This option applies to the chart's Prometheus, **not external scrapers such as
Grafana Alloy**. Sites using an external scraper must provide their own scoped,
rotated credential Secrets and set each component's
`serviceMonitor.authorization`. Secrets must be in the ServiceMonitor namespace;
`ignoreNamespaceSelectors: true` changes the control-plane namespace assumptions.
A component selecting a different `serviceMonitor.scrapeClass` keeps its own
authorization; audit every override. Do not set `authorization: null` as a way to
avoid a token: that means anonymous scraping and can break coverage.

Namespace confinement is a site-specific choice: `prometheusOperator.namespaces`,
`prometheusOperator.denyNamespaces`, and
`prometheus.prometheusSpec.serviceMonitorNamespaceSelector` /
`podMonitorNamespaceSelector` restrict discovery, but do not by themselves shrink
the operator's ClusterRole. DeepOps retains cluster-wide monitoring coverage;
restricted-RBAC sites must supply reviewed Roles/Bindings with
`global.rbac.create: false`, preserve necessary discovery permissions, and verify
all targets. Do not silently remove monitoring permissions or CRDs.

## Before upgrading

Run only against a reviewed inventory/context and an approved maintenance window.
Plan for pod restarts and temporarily unavailable dashboards/metrics. Review
capacity, PVC health and custom values; take a recoverable storage snapshot of
Prometheus data and retain the original chart package. Never use the installer's
`-d` delete option for an upgrade or rollback.

Save Helm values/manifests and monitoring custom resources privately: they can
contain credentials. Do not print or attach them to public reports.

```bash
umask 077
mkdir -p monitoring-upgrade-backup
helm list -n monitoring
helm get values kube-prometheus-stack -n monitoring -o yaml > monitoring-upgrade-backup/values.yaml
helm get manifest kube-prometheus-stack -n monitoring > monitoring-upgrade-backup/manifest.yaml
kubectl get crd -o yaml > monitoring-upgrade-backup/crds.yaml
kubectl get prometheuses,alertmanagers,alertmanagerconfigs,prometheusagents,prometheusrules,servicemonitors,podmonitors,probes,scrapeconfigs,thanosrulers -A -o yaml > monitoring-upgrade-backup/monitoring-resources.yaml
```

Compare custom values to the target, including all removed authorization/TLS
keys listed in upstream's 90.x notes. Copy the rotating-token settings above into
**both** local values files if used. Do not overwrite site settings with examples
or blindly use `--reuse-values`: Helm can preserve removed keys and old defaults.
Keep ingress addresses, persistence, resource sizing and dashboard settings.
The installer injects the three `*.ingress.hosts` lists and optional image
repository overrides via `--set`; these live in the saved Helm user values,
not necessarily in `config/helm/monitoring.yml`. Audit and migrate
`monitoring-upgrade-backup/values.yaml` for the target chart, removing obsolete
keys and translating any changed image keys. The upgrade below loads these
reviewed saved values **first**, then the reviewed site file **second** so new
rotating-token settings win. Confirm the resulting ingress hosts and image
repositories with a private `helm template` render before applying; do not
attach rendered Secrets or values. This is an explicit values merge, not
`--reuse-values` (which also retains old chart defaults).

In particular, legacy installer overrides such as `image.repository`,
`prometheus.image.repository`, `alertmanager.image.repository`, and
`grafana.grafanaWatcher.repository` are not the target chart's effective keys.
Translate operator/Prometheus/Alertmanager mirrors to
`prometheusOperator.image`, `prometheus.prometheusSpec.image`, and
`alertmanager.alertmanagerSpec.image` (`registry` plus repository path), and
Grafana watcher mirrors to `grafana.sidecar.image`. Grafana's main image uses
`grafana.image.registry` plus `grafana.image.repository`; do not leave a full
registry/path in `repository` while the default `registry` is still set.
Inspect tags/digests and auxiliary images too; retaining a stale unused key is
not proof of an air-gapped image override.

## Update CRDs first, then Helm

Ordinary Helm upgrades do not upgrade CRDs automatically. Use the CRDs bundled
with the **exact pinned chart** (including its CRD subchart), not `main` or the
v0.94.0 links from the 91.x notes:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm pull prometheus-community/kube-prometheus-stack --version 92.14.0 --destination monitoring-upgrade-backup
helm show crds monitoring-upgrade-backup/kube-prometheus-stack-92.14.0.tgz > monitoring-upgrade-backup/target-crds.yaml
# Inspect: expected 10 monitoring.coreos.com CRDs, from operator v0.94.2.
kubectl apply --server-side --dry-run=server -f monitoring-upgrade-backup/target-crds.yaml
kubectl apply --server-side -f monitoring-upgrade-backup/target-crds.yaml
kubectl wait --for=condition=Established --timeout=120s -f monitoring-upgrade-backup/target-crds.yaml
helm upgrade kube-prometheus-stack monitoring-upgrade-backup/kube-prometheus-stack-92.14.0.tgz \
  --namespace monitoring \
  --values monitoring-upgrade-backup/values.yaml \
  --values config/helm/monitoring.yml --wait --timeout 1200s
```

For a deliberately nonpersistent installation substitute its reviewed
`monitoring-no-persist.yml`; do not switch an existing persistent release to it.
Resolve server-side field conflicts deliberately; do not blindly add
`--force-conflicts`. Do not enable `crds.upgradeJob.enabled` as well as manually
applying CRDs: that alternative introduces a privileged CRD-upgrade job needing
its own review. `scripts/k8s/deploy_monitoring.sh` installs missing/failed releases
but **skips healthy deployed releases**, so use the explicit upgrade above.

## Required verification

- Helm reports version 92.14.0 and state `deployed`; operator and workloads roll
  out successfully without RBAC denials or CRD/schema errors.
- All 10 CRDs are Established; custom monitoring objects remain present and
  reconciliation succeeds. Record CRD versions and operator image, not secret data.
- No new `kubernetes.io/service-account-token` Secret exists for Prometheus.
  Rendered Prometheus has the rotating-token scrape class, and each enabled
  control-plane ServiceMonitor selects it. Inspect generated scrape configuration
  privately; never print token values or credential contents.
- `kubectl auth can-i --as=system:serviceaccount:monitoring:kube-prometheus-stack-prometheus`
  proves expected discovery and metrics permissions; operator service-account
  checks cover its CRD/status/reconciliation permissions. Record positive and
  negative checks (e.g. Prometheus cannot mutate nodes or create clusterroles).
- Prometheus `/api/v1/targets` shows expected API server, kubelet, DNS and enabled
  controller-manager/scheduler/etcd/proxy targets healthy; compare with 88.6.5.
  Distinguish pre-existing disabled/unreachable targets from new failures.
  Repeat through at least one projected-token rotation. CRD presence or `can-i`
  alone is not successful scrape authorization proof.
- Existing dashboards and GPU/DCGM metrics still work. Verify persistent data
  survives the upgrade and Linux scheduling selectors retain site placement.
- Run:ai platform's chart floor remains **88.6.5**. 92.14.0 satisfies that numeric
  preflight; this is not a certification of Run:ai runtime compatibility.

For local render checks, unpack the exact chart and run:

```bash
KPS_CHART_DIR=/path/to/kube-prometheus-stack \
  python3 -m unittest discover -s scripts/validation/tests -p test_monitoring_chart.py -v
```

## Failure and recovery

Save diagnostics privately and stop if credentials, reconciliation, data or
control-plane target coverage regress. Helm rollback can revert workload
manifests but **does not downgrade CRDs or restore lost data**. Before any rollback,
check whether the previous operator works with the new schemas; rehearse this on
the test cluster and retain a storage snapshot. Do not delete CRDs or the
monitoring namespace: this can destroy custom resources and retained metrics.
A CRD/schema or data restore requires an explicit recovery plan and approval.
