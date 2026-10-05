#!/usr/bin/env python3
"""Check explicitly required model files locally; never download or load model code."""
import argparse
import json
from pathlib import Path, PurePosixPath
import re
import stat
import sys


class CacheError(Exception):
    """An absent or unsafe cache input."""


def validate(cache_dir, repo_id, revision, required_files):
    result = {
        "schema_version": 1,
        "ok": False,
        "repo_id": repo_id,
        "revision": revision,
        "snapshot_path": None,
        "checked_files": [],
        "errors": [],
    }
    try:
        parts = repo_id.split("/")
        if (len(parts) not in (1, 2) or len(repo_id) > 96
                or any(not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", p)
                       or p.endswith((".", "-")) or ".." in p or "--" in p for p in parts)):
            raise CacheError("repo_id must be a model name or namespace/model name")
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise CacheError("revision must be a full lowercase 40-character commit hash")
        for name in required_files:
            path = PurePosixPath(name)
            if (not name or path.is_absolute() or ".." in path.parts
                    or str(path) != name or name == "." or "\\" in name):
                raise CacheError("required files must be normalized relative paths without traversal")
        root = Path(cache_dir).resolve(strict=True)
        if not root.is_dir():
            raise CacheError("cache directory is not a directory")
        snapshot = root / ("models--" + repo_id.replace("/", "--")) / "snapshots" / revision
        # Reject redirected repository/snapshot directories. Blob symlinks are expected.
        if snapshot.resolve(strict=True) != snapshot or not snapshot.is_dir():
            raise CacheError("snapshot directory is missing or redirected")
        result["snapshot_path"] = str(snapshot)
        for name in dict.fromkeys(required_files):
            target = (snapshot / name).resolve(strict=True)
            try:
                target.relative_to(root)
            except ValueError:
                raise CacheError("required file resolves outside the cache") from None
            info = target.stat()
            if not stat.S_ISREG(info.st_mode) or info.st_size == 0:
                raise CacheError("required file is not a nonempty regular file: " + name)
            with target.open("rb") as stream:
                if not stream.read(1):
                    raise CacheError("required file is empty: " + name)
            result["checked_files"].append(name)
        result["ok"] = True
    except CacheError as exc:
        result["errors"].append(str(exc))
    except (OSError, RuntimeError, ValueError):
        # Do not echo OS exception paths: a malformed symlink can point at private data.
        result["errors"].append("cache input missing, unreadable, or invalid; check the pinned snapshot and required files")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", required=True, help="Explicit HF_HUB_CACHE directory")
    parser.add_argument("--repo-id", required=True, help="Model repository, e.g. namespace/model")
    parser.add_argument("--revision", required=True, help="Full immutable model commit hash")
    parser.add_argument("--require-file", action="append", required=True,
                        help="Required nonempty file relative to snapshot; repeat for every needed file")
    parser.add_argument("--json", action="store_true", help="Emit schema-versioned JSON")
    args = parser.parse_args()
    result = validate(args.cache_dir, args.repo_id, args.revision, args.require_file)
    if args.json:
        print(json.dumps(result, sort_keys=True))
    elif result["ok"]:
        print("PASS: required files readable at " + result["snapshot_path"])
    else:
        print("FAIL: " + "; ".join(result["errors"]))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
