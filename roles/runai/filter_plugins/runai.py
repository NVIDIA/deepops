"""Small helpers for the runai role (pure functions, unit tested)."""
import re


def runai_deep_merge(base, extra):
    """Recursively merge ``extra`` over ``base`` (dicts merge, everything else replaces)."""
    out = dict(base)
    for key, value in (extra or {}).items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = runai_deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def runai_password_ok(value):
    """Run:ai admin password policy: 8+ chars, digit, lower, upper, special from -!@#$%^&*()_+="""
    return bool(
        isinstance(value, str) and len(value) >= 8
        and re.search(r"[0-9]", value) and re.search(r"[a-z]", value)
        and re.search(r"[A-Z]", value) and re.search(r"[-!@#$%^&*()_+=]", value)
    )


def _items(doc):
    if isinstance(doc, str):
        import json
        doc = json.loads(doc)
    return (doc or {}).get("items", [])


def runai_gpu_count(nodes_doc):
    """Total allocatable nvidia.com/gpu across a ``kubectl get nodes -o json`` document."""
    total = 0
    for item in _items(nodes_doc):
        value = ((item.get("status") or {}).get("allocatable") or {}).get("nvidia.com/gpu", "0")
        try:
            total += max(int(value), 0)
        except (TypeError, ValueError):
            pass
    return total


def runai_driver_majors(nodes_doc):
    """Driver major version (int) for every node labelled nvidia.com/gpu.present."""
    out = []
    for item in _items(nodes_doc):
        labels = (item.get("metadata") or {}).get("labels") or {}
        if "nvidia.com/gpu.present" not in labels:
            continue
        try:
            out.append(int(labels.get("nvidia.com/cuda.driver-version.major", "0")))
        except (TypeError, ValueError):
            out.append(0)
    return out


def runai_default_storageclasses(sc_doc):
    """Names of default StorageClasses in a ``kubectl get storageclass -o json`` document."""
    out = []
    for item in _items(sc_doc):
        meta = item.get("metadata") or {}
        ann = meta.get("annotations") or {}
        if ann.get("storageclass.kubernetes.io/is-default-class") == "true":
            out.append(meta.get("name", ""))
    return out


class FilterModule(object):
    def filters(self):
        return {
            "runai_deep_merge": runai_deep_merge,
            "runai_gpu_count": runai_gpu_count,
            "runai_driver_majors": runai_driver_majors,
            "runai_default_storageclasses": runai_default_storageclasses,
            "runai_password_ok": runai_password_ok,
        }
