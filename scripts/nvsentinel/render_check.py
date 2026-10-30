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
        check(("janitor" in deploys) == (lvl >= 3), f"{tag}: janitor presence wrong")
        check(("fault-quarantine" in deploys) == (lvl >= 1), f"{tag}: fault-quarantine presence wrong")
        check(("fault-remediation" in deploys) == (lvl >= 3), f"{tag}: fault-remediation presence wrong")
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
            ba = breaker_args(docs)
            check(ba is not None and "circuit-breaker" in ba.lower(), f"{tag}: breaker arg")

# dry-run goes through the global key only
t = render_values(nvsentinel_mode="cordon", nvsentinel_db_members=1, nvsentinel_gpu_node_count=3, nvsentinel_dry_run=True)
docs, err = helm(t)
check(docs is not None and "--dry-run=true" in " ".join(
    a for d in docs if d.get("kind") == "Deployment" for c in d["spec"]["template"]["spec"]["containers"]
    for a in c.get("args", [])), "dryRun=true not rendered via global.dryRun")
check(not any(k in yaml.safe_load(t) for k in ("fault-quarantine",)) or "dryRun" not in yaml.safe_load(t)["fault-quarantine"],
      "per-module dryRun key present")

if fails:
    print("FAIL"); [print(" -", f) for f in fails]; sys.exit(1)
print("OK: all render checks passed")
