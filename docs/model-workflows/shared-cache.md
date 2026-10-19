# Shared model cache

Use the open-source Hugging Face `hf` CLI to download an approved model once
onto existing NFS storage. One designated writer populates the cache; Slurm
jobs and Kubernetes pods consume pinned snapshots read-only. No paid service,
registry entitlement, inference service, or model-management daemon is required.
Model licenses and gated-repository access remain the operator's responsibility.

This opt-in example does **not** mount/export storage, create accounts, install
packages on cluster nodes, download weights automatically, or alter cluster-wide
environment variables. It is not part of either cluster deployment playbook.

## Prerequisites and trust boundary

- Existing NFS mount at the **same path** on the writer and readers, with working
  POSIX locks and symlinks. The site owns export options, capacity, backups,
  availability and consistent numeric user/group IDs. Test those on the actual
  filesystem before downloading models. This example does not certify NFS.
- A dedicated existing writer account (example: `model-writer`) and reader group
  (`model-readers`). The writer belongs to that group and can create a directory
  at the mount root. Readers can traverse the mount and belong to that group.
  Root-squashed NFS is supported by doing cache writes **as the writer**, not root.
- Every reader is authorized to read **every model in this cache**. Use separate
  caches/access groups for restricted models. Read-only storage is not a license
  or entitlement check. Do not make this cache world-readable or group-writable.
- Only trusted operators can write the cache or its parent. Pause writers while
  validating/publishing a snapshot; the validator is not a defense against a
  malicious writer racing file changes. Never load unreviewed model code.
- Python 3.10+ with venv support on the writer, plus the usual DeepOps Ansible
  environment on the provisioning machine. Use a separate environment for `hf`;
  do not upgrade Ansible's or the serving application's Python dependencies.

Keep **`HF_HOME`, `HF_TOKEN_PATH` and `HF_XET_CACHE` private and outside shared
storage**. Only `HF_HUB_CACHE` is shared. `HF_HOME` contains authentication data;
sharing it can expose credentials. Do not write tokens into inventory, commands,
logs, images, or the environment file. Public models need no login. For gated
models, obtain access separately using the writer's private `hf auth login`.

## 1. Prepare the cache (provisioning machine)

Add exactly one host to `[model-cache-warmer]` in `config/inventory`. In
`config/group_vars/model-cache-warmer.yml` set site-owned values, for example:

```yaml
model_cache_mount: /shared
model_cache_owner: model-writer
model_cache_group: model-readers
# Optional: a dedicated direct child of the mount. Default shown:
model_cache_root: /shared/hf-cache
```

Review the inventory and preview before applying:

```bash
ansible-inventory -i config/inventory --graph
ansible-playbook -i config/inventory playbooks/model-cache.yml --check --diff
ansible-playbook -i config/inventory playbooks/model-cache.yml
```

The playbook fails if the mount is absent or is not NFS, more than one writer is
selected, or cache directories are symlinks. It creates `hf-cache/` and `hub/`
with writer ownership and mode `2750` (group read/traverse, not write). It writes
`environment.sh` with mode `0640`, exporting only `HF_HUB_CACHE`. Existing cache
contents are **not** recursively re-owned or permission-repaired. A rerun should
report `changed=0`; audit pre-existing files separately.

## 2. Populate a fixed revision (writer account)

Install the train's pinned CLI in a private virtual environment:

```bash
python3 -m venv "$HOME/.venvs/model-cache"
"$HOME/.venvs/model-cache/bin/python" -m pip install -r examples/model-cache/requirements.txt
"$HOME/.venvs/model-cache/bin/hf" version
```

From a shell running as the designated writer, use a restrictive umask and source
only the cache environment. This example model is public; review its license,
file list and size before downloading. The commit hash, not `main` or a tag, is
the reproducibility boundary:

```bash
umask 0027
. /shared/hf-cache/environment.sh
export MODEL_ID=openai-community/gpt2
export MODEL_REVISION=607a30d783dfa663caf39e06633721c8d4cfcd7e
"$HOME/.venvs/model-cache/bin/hf" download "$MODEL_ID" \
  config.json tokenizer.json model.safetensors \
  --revision "$MODEL_REVISION" --cache-dir "$HF_HUB_CACHE"
```

For another model, explicitly list all needed configuration, tokenizer and weight
files. For sharded weights, include the index **and every referenced shard**.
A successful download of `config.json` alone does not make a usable model.
Do not use `--local-dir` here: that creates a different layout than the shared Hub
cache consumed by the validator. Never populate from every compute process.

`huggingface_hub==2.1.1` supplies `hf`; `hf-xet` is a normal dependency on supported
platforms. Do not install or enable the deprecated `hf_transfer`. Leave Xet's
private cache on local storage. The v2 cache can link repository blobs to a
shared top-level blob store: preserve the **whole hub directory** and symlinks
when transferring it, not just a snapshot directory.

## 3. Validate as the consumer, then load a local snapshot

On a reader node (or inside the actual workload container, with its real UID and
mount), run the validator from the repository root:

```bash
python3 scripts/validation/validate_model_cache.py --json \
  --cache-dir /shared/hf-cache/hub \
  --repo-id openai-community/gpt2 \
  --revision 607a30d783dfa663caf39e06633721c8d4cfcd7e \
  --require-file config.json \
  --require-file tokenizer.json \
  --require-file model.safetensors
```

Exit `0` and `"ok": true` mean that **only the explicitly required files** are
nonempty, regular, readable files inside the selected cache. Exit `1` means
validation failed; exit `2` means invalid command syntax. JSON schema version `1`
contains `ok`, `repo_id`, `revision`, `snapshot_path`, `checked_files`, and `errors`.
The check uses only the Python standard library; it never downloads, installs,
writes cache data, imports a model, or contacts an endpoint. It does not prove
checksums, complete model coverage, mount health, locking, GPU compatibility, or
inference quality. Review the required file list and run the workload's own test.

Use the returned `snapshot_path` as the application's **local model path**.
Mount the entire cache read-only in containers, at the path used for validation;
relative blob links need their parent directories. Keep tokenizer assets together
with weights. A Slurm job uses the same path on each allocated node; in Kubernetes,
use a site-provided volume with `readOnly: true` and matching reader group access.
This playbook does not provision a volume or choose the workload's security context.

For disconnected readers, scope `HF_HUB_OFFLINE=1` to the model-loading process.
It suppresses Hub HTTP and fails on cache misses, but is **not a network firewall**.
It also blocks Hugging Face client HTTP to local inference endpoints; do not set
it in clients that must call a local server. Prefer a local snapshot path and
site-enforced egress restrictions. See [air-gapped deployment](../../skills/deploy-airgapped/SKILL.md)
for the separate package/image mirroring requirements. The writer's pinned Python
packages must also be mirrored before using it offline.

## Failure handling and lifecycle

- Missing mount: stop and have the storage operator restore the approved mount.
  Never remove the mount guard or download into the underlying local directory.
- Permission error: check numeric IDs, group membership, mount/export options and
  traversal permissions as the workload user. Never fix with `chmod -R 777`.
- Missing/partial file: rerun the same pinned `hf download` as the writer, then
  validate again as a reader. Do not claim readiness from directory existence.
- Broken links after transfer: recopy the entire cache preserving symlinks and
  top-level blobs. Do not copy credentials or private Xet state with it.
- Validation success but loading failure: check the **complete model-specific
  file list** and framework compatibility; a file-presence check is not inference.
- No automatic cleanup: keep snapshots while any job uses them. `hf cache prune`
  can remove commit-pinned snapshots without named refs. Do not run it routinely
  or during workloads. Review retention explicitly and back up before deletion;
  old clients may mishandle the v2 shared blob store.
- Dataset processing caches are not this model cache. Keep them per environment.

## Development checks

```bash
python3 -m unittest discover -s scripts/validation/tests -p 'test_model_cache*.py'
ansible-playbook --syntax-check -i localhost, playbooks/model-cache.yml
```

The playbook tests run its real tasks against scratch directories with synthetic
NFS facts, proving guards/permissions/idempotence without mounting storage. Live
cross-user NFS and actual model loading remain separate validation gates.

## Primary sources (verified 2026-10-05)

- [Hub v2.1.1 source](https://github.com/huggingface/huggingface_hub/tree/v2.1.1)
  and [published package](https://pypi.org/project/huggingface-hub/2.1.1/).
  GitHub's latest release entry still points at v2.1.0; v2.1.1 is the published
  patch and documented CLI version, so this example pins 2.1.1 explicitly.
- [CLI guide](https://huggingface.co/docs/huggingface_hub/v2.1.1/en/guides/cli),
  [environment variables](https://huggingface.co/docs/huggingface_hub/v2.1.1/en/package_reference/environment_variables),
  [cache layout](https://huggingface.co/docs/huggingface_hub/v2.1.1/en/guides/manage-cache).
- [vLLM v0.31.0](https://github.com/vllm-project/vllm/releases/tag/v0.31.0)
  is the serving release observed on this date; its
  [requirements](https://github.com/vllm-project/vllm/blob/v0.31.0/requirements/common.txt)
  specify `huggingface_hub >= 1.31.0`. This cache change neither installs vLLM
  nor claims a tested serving combination. Re-check and validate the serving
  environment separately; a minimum requirement is not compatibility evidence.
