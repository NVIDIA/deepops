---
name: manage-model-cache
description: Use when preparing a shared Hugging Face model cache for Slurm or Kubernetes, pinning downloaded model revisions, validating offline model files, or diagnosing missing snapshots and cache permissions.
---

# Manage a shared model cache

Run commands from the DeepOps repository root. This skill prepares model files,
not inference services. Read [the cache guide](../../docs/model-workflows/shared-cache.md)
for the supported CLI version, exact configuration and working download example.

## Preconditions

1. Confirm the approved existing NFS mount, one designated writer account,
   reader group, model license/access, available capacity and immutable revision.
   Do not create mounts, change exports, create users, or grant access implicitly.
2. Review `config/inventory` and `config/group_vars/model-cache-warmer.yml`.
   Exactly one host belongs to `model-cache-warmer`. All readers need matching
   numeric group IDs and an existing mount at the intended workload path.
3. Keep `HF_HOME`, `HF_TOKEN_PATH` and `HF_XET_CACHE` private; share only
   `HF_HUB_CACHE`. Never share authentication storage or paste credentials into commands.
4. Use a private Python 3.10+ environment for `examples/model-cache/requirements.txt`.
   Do not install into Ansible's or the serving framework's environment. No login
   or paid service is needed for the public example.

## Procedure and gates

1. Preview `ansible-playbook -i config/inventory playbooks/model-cache.yml --check --diff`.
   Apply without `--check --diff` only to the approved writer and cache path.
   The playbook must finish with `failed=0`; repeat once to check `changed=0`.
   A successful playbook **does not mean a model is cached**.
2. As the writer, use `umask 0027`, source the generated `environment.sh`, and run
   the pinned `hf download` with a **full commit hash** and the approved file list
   as shown in the guide. Include every tokenizer/config file and weight shard
   required by the workload. Do not use `main`, `--local-dir`, or deprecated
   `hf_transfer`; do not have compute jobs warm the cache themselves.
3. Stop writes to the selected snapshot. As the actual reader UID, in the actual
   workload mount context, run `python3 scripts/validation/validate_model_cache.py`
   with `--json`, `--cache-dir`, `--repo-id`, `--revision`, and one `--require-file`
   per needed file. The guide has a complete command for the public example.
4. Accept only exit `0` **and** `ok: true`. Record revision, `checked_files` and
   `snapshot_path`. Pass that local path to the application and mount the entire
   cache read-only. The validator checks presence/readability, **not** checksums,
   complete model coverage, NFS locking, successful inference or GPU suitability.
5. For offline model loading, set `HF_HUB_OFFLINE=1` only in the loading process.
   Do not apply it to a Hugging Face client calling a local inference server:
   it blocks that HTTP too. Offline mode is not a network access control.

## Stop and recovery branches

| Observation | Next action |
|---|---|
| No NFS mount / wrong filesystem | Stop. Ask the storage owner to restore the approved mount; never bypass the guard. |
| `ok: false`, missing or broken file | Rerun the same pinned download as the writer, then revalidate as the reader. Never infer readiness from a directory. |
| Permission denied | Check group IDs and traversal/read permissions. Do not make the cache world-readable or use recursive `777`. |
| Valid file list but application fails | Check model-specific files and serving compatibility. File presence alone is not a serving test. |
| Interrupted/offline transfer | Transfer the whole Hub cache preserving links, including top-level shared blobs. Do not transfer private auth or Xet state. |
| Space pressure | Stop new downloads; arrange operator-reviewed retention. No automatic prune: pinned snapshots may have no named refs and still be in use. |

Do not run a server, enable remote model code, start paid jobs, delete snapshots,
or change a live cluster as an inferred continuation of this skill.
