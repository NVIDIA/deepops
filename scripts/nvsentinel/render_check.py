#!/usr/bin/env python3
"""Render roles/nvsentinel/templates/values.yaml.j2 for each mode / size /
GPU-node count, run `helm template` on the pinned chart, and assert the result."""
import json, os, subprocess, sys, tempfile
import jinja2, yaml

TEMPLATE = os.environ["NVSENTINEL_TEMPLATE"]
CHART = os.environ["NVSENTINEL_CHART"]
MODES = ["observe", "cordon", "drain", "remediate"]
fails = []


def check(cond, msg):
    if not cond:
        fails.append(msg)


def get(d, path, default=None):
    for k in path.split("."):
        if not isinstance(d, dict) or k not in d:
            return default
        d = d[k]
    return d


def render_values(**v):
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(os.path.dirname(TEMPLATE)),
                             trim_blocks=True, lstrip_blocks=False)
    env.filters["to_json"] = json.dumps
    env.filters["bool"] = lambda x: x if isinstance(x, bool) else str(x).lower() in ("1", "true", "yes")
    return env.get_template(os.path.basename(TEMPLATE)).render(**v)


def helm(values_text):
    with tempfile.NamedTemporaryFile("w", suffix=".yaml") as f:
        f.write(values_text); f.flush()
        out = subprocess.run(["helm", "template", "nvsentinel", CHART, "-n", "nvsentinel", "-f", f.name],
                             capture_output=True, text=True)
    if out.returncode:
        return None, out.stderr
    return [d for d in yaml.safe_load_all(out.stdout) if d], ""


def names(docs, kind=None):
    return [d["metadata"]["name"] for d in docs if kind is None or d.get("kind") == kind]


def breaker_args(docs):
    for d in docs:
        if d.get("kind") == "Deployment" and "fault-quarantine" in d["metadata"]["name"]:
            c = d["spec"]["template"]["spec"]["containers"][0]
            return " ".join(c.get("args", []))
    return None


for mode in MODES:
    lvl = MODES.index(mode)
    for members, gpus in [(1, 1), (1, 3), (1, 12), (3, 3), (3, 12)]:
        tag = f"{mode}/db{members}/gpu{gpus}"
        text = render_values(nvsentinel_mode=mode, nvsentinel_db_members=members,
                             nvsentinel_gpu_node_count=gpus, nvsentinel_storage_class="local-path",
                             nvsentinel_priority_class="system-cluster-critical", nvsentinel_dry_run=False)
        v = yaml.safe_load(text)
        g = v["global"]
        # explicit switches
        for key, minlvl in [("faultQuarantine", 1), ("mongodbStore", 1), ("nodeDrainer", 2),
                            ("faultRemediation", 3), ("janitor", 3), ("janitorProvider", 3)]:
            check(g[key]["enabled"] is (lvl >= minlvl), f"{tag}: global.{key}.enabled wrong")
        check(g["dryRun"] is False, f"{tag}: dryRun")
        excl = get(v, "janitor.config.nodes.exclusions")
        check(excl and excl[0] == {"matchLabels": {"node-role.kubernetes.io/control-plane": ""}},
              f"{tag}: janitor control-plane exclusion missing")
        if lvl >= 1:
            db = v["mongodb-store"]
            check(db["useBitnami"] is False and db["usePerconaOperator"] is True, f"{tag}: percona flags")
            rs = get(db, "psmdb-db.replsets.rs0")
            check(rs["size"] == members, f"{tag}: size")
            check(get(db, "psmdb-db.unsafeFlags.replsetSize") is (members < 3), f"{tag}: unsafeFlags")
            check(("replsetOverrides" in rs and rs["replsetOverrides"] is None) == (members < 3),
                  f"{tag}: replsetOverrides null only at size<3")
            check(get(rs, "volumeSpec.pvc.storageClassName") == "local-path", f"{tag}: storageClassName")
            check(rs.get("priorityClass") == "system-cluster-critical", f"{tag}: priorityClass")
            check(get(db, "psmdb-operator.disableTelemetry") is True, f"{tag}: telemetry")
            check(get(db, "psmdb-db.upgradeOptions.apply") == "disabled", f"{tag}: upgradeOptions")
            exp = 100 if gpus < 10 else 50
            check(get(v, "fault-quarantine.circuitBreaker.percentage") == exp
                  and get(v, "fault-quarantine.circuitBreaker.enabled") is True, f"{tag}: breaker")
        else:
            check("mongodb-store" not in v and "fault-quarantine" not in v, f"{tag}: observe has db/breaker keys")
        if lvl >= 2:
            check(v["node-drainer"]["userNamespaces"] == [{"name": "*", "mode": "AllowCompletion"}], f"{tag}: drain policy")
        if lvl >= 3:
            check(get(v, "janitor-provider.csp.provider") == "generic", f"{tag}: janitor provider")

        docs, err = helm(text)
        if docs is None:
            check(False, f"{tag}: helm template failed: {err.strip()[:300]}")
            continue
        deploys = " ".join(names(docs, "Deployment") + names(docs, "DaemonSet"))
        check(("drainer" in deploys) == (lvl >= 2), f"{tag}: node-drainer presence wrong")
        dn = names(docs, "Deployment")
        check(("janitor" in dn) == (lvl >= 3) and ("janitor-provider" in dn) == (lvl >= 3), f"{tag}: janitor/janitor-provider presence wrong")
        check(("fault-quarantine" in deploys) == (lvl >= 1), f"{tag}: fault-quarantine presence wrong")
        check(("fault-remediation" in deploys) == (lvl >= 3), f"{tag}: fault-remediation presence wrong")
        if lvl >= 3:
            check("node-role.kubernetes.io/control-plane" in yaml.dump(
                  [d for d in docs if d.get("kind") == "ConfigMap" and "janitor" in d["metadata"]["name"]]),
                  f"{tag}: rendered janitor config lacks control-plane exclusion")
        kinds = {d.get("kind") for d in docs}
        check(("PerconaServerMongoDB" in kinds) == (lvl >= 1), f"{tag}: PerconaServerMongoDB presence")
        check("StatefulSet" not in kinds or lvl >= 1, f"{tag}: unexpected StatefulSet")
        if lvl >= 1:
            psmdb = [d for d in docs if d.get("kind") == "PerconaServerMongoDB"][0]
            r0 = psmdb["spec"]["replsets"][0]
            check(r0["size"] == members, f"{tag}: rendered size")
            check(get(r0, "volumeSpec.persistentVolumeClaim.storageClassName") == "local-path",
                  f"{tag}: rendered storageClassName")
            check(not (members < 3 and r0.get("replsetOverrides")), f"{tag}: rendered overrides at size 1")
            check(bool(r0.get("replsetOverrides")) == (members >= 3), f"{tag}: upstream overrides kept at 3")
            check(get(psmdb, "spec.upgradeOptions.apply") == "disabled", f"{tag}: rendered upgradeOptions")
            ops = [d for d in docs if d.get("kind") == "Deployment" and "psmdb-operator" in d["metadata"]["name"]]
            envs = [e for d in ops for c in d["spec"]["template"]["spec"]["containers"] for e in c.get("env", [])]
            check(any(e.get("name") == "DISABLE_TELEMETRY" and str(e.get("value")).lower() == "true" for e in envs),
                  f"{tag}: rendered DISABLE_TELEMETRY")
            ba = breaker_args(docs)
            check(ba is not None and "--circuit-breaker-enabled=true" in ba, f"{tag}: breaker arg")

# dry-run goes through the global key only
t = render_values(nvsentinel_mode="cordon", nvsentinel_db_members=1, nvsentinel_gpu_node_count=3, nvsentinel_dry_run=True)
docs, err = helm(t)
check(docs is not None and "--dry-run=true" in " ".join(
    a for d in docs if d.get("kind") == "Deployment" for c in d["spec"]["template"]["spec"]["containers"]
    for a in c.get("args", [])), "dryRun=true not rendered via global.dryRun")
check(all("dryRun" not in (m if isinstance(m, dict) else {}) for k, m in yaml.safe_load(t).items() if k != "global"),
      "per-module dryRun key present")

# precedence: role-resolved effective_* inputs beat public ones (-e overrides)
t = yaml.safe_load(render_values(nvsentinel_mode="cordon", nvsentinel_effective_mode="observe",
                                 nvsentinel_gpu_node_count=3, nvsentinel_effective_gpu_node_count=12,
                                 nvsentinel_db_members=3, nvsentinel_pod_monitor=True,
                                 nvsentinel_pod_monitor_available=False))
check(t["global"]["faultQuarantine"]["enabled"] is False and "mongodb-store" not in t, "effective_mode must beat nvsentinel_mode")
check(t["podMonitor"]["enabled"] is False, "pod_monitor_available=false must beat nvsentinel_pod_monitor=true")
t = yaml.safe_load(render_values(nvsentinel_mode="cordon", nvsentinel_gpu_node_count=3,
                                 nvsentinel_effective_gpu_node_count=12, nvsentinel_db_members=1))
check(t["fault-quarantine"]["circuitBreaker"]["percentage"] == 50, "effective_gpu_node_count must beat public count")
t = yaml.safe_load(render_values(nvsentinel_mode="drain", nvsentinel_gpu_node_count=12, nvsentinel_db_members=1,
                                 nvsentinel_pod_monitor=True))
check(t["global"]["nodeDrainer"]["enabled"] is True and t["podMonitor"]["enabled"] is True
      and t["fault-quarantine"]["circuitBreaker"]["percentage"] == 50, "public fallback when effective_* unset")
check(yaml.safe_load(render_values(nvsentinel_mode="cordon", nvsentinel_effective_mode="cordon",
      nvsentinel_pod_monitor_available=True))["podMonitor"]["enabled"] is True, "pod_monitor_available=true")
# driver fallback
check(yaml.safe_load(render_values(nvsentinel_mode="observe", gpu_operator_preinstalled_nvidia_software=False))
      ["labeler"]["assumeDriverInstalled"] is False, "driver fallback to gpu_operator_preinstalled_nvidia_software")
check(yaml.safe_load(render_values(nvsentinel_mode="observe"))["labeler"]["assumeDriverInstalled"] is True, "driver default true")
# Percona: no systemUsers in values or rendered CR (operator generates credentials on cluster)
for m in ("cordon", "remediate"):
    tx = render_values(nvsentinel_mode=m, nvsentinel_db_members=3, nvsentinel_gpu_node_count=3)
    check("systemUsers" not in tx, f"{m}: systemUsers present in values")
    docs, _ = helm(tx)
    for d in docs or []:
        if d.get("kind") == "PerconaServerMongoDB":
            check("systemUsers" not in d["spec"], f"{m}: rendered CR has spec.systemUsers")
            check("secrets" not in d["spec"] or "users" not in d["spec"].get("secrets", {}), f"{m}: rendered CR names users secret")

if fails:
    print("FAIL"); [print(" -", f) for f in fails]; sys.exit(1)
print("OK: all render checks passed")
