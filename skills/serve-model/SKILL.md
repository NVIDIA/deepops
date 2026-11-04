---
name: serve-model
description: Use when serving a cached model on one GPU with vLLM, checking a local completion endpoint, or diagnosing startup and inference failures in the single-node quickstart.
---

# Serve a model on one node

Run from the repository root on the allocated serving node. Read the
[vLLM quickstart](../../docs/model-workflows/vllm-quickstart.md) for the exact
installation and foreground launch commands. This skill does not allocate a GPU
or authorize a workload.

## Preconditions

- Confirm permission for the node, one isolated GPU, package installation,
  server startup and the validator's inference request. Record the allocation
  and the process you own. Never use a login shell outside that allocation or
  override scheduler device isolation.
- Confirm model license, immutable revision, complete file list, reader identity,
  cache mount and served alias. Use [manage-model-cache](../manage-model-cache/SKILL.md)
  for missing files; do not make consumers download them.
- Require Python 3.12 and a fresh private serving environment using
  `examples/vllm/requirements.txt`. Check wheel/driver compatibility against the
  quickstart; do not change drivers or the cache writer's environment.
- Keep the whole Hub cache read-only, including blobs. Keep authentication,
  `HF_HOME`, Xet and framework caches private. Pause snapshot writes during use.

## Procedure and success gate

1. Follow quickstart steps 1–2. Require cache validator exit `0` **and** `ok: true`
   as the actual reader before startup. Config alone is not a complete model;
   name every required weight shard and tokenizer file.
2. Use quickstart step 3 unchanged for the public example: local snapshot and
   tokenizer, offline loading, one GPU, foreground process, loopback only. Never
   enable remote model code. `HF_HUB_OFFLINE=1` is not a firewall and belongs only
   on the loading process, not globally on clients.
3. Wait for startup; use another shell in the same allocation and namespace to
   validate. This submits inference, not just a read-only health check:

```bash
python3 scripts/validation/validate_vllm.py --json \
  --base-url http://127.0.0.1:8000 --model deepops-gpt2 \
  --cache-dir /shared/hf-cache/hub \
  --repo-id openai-community/gpt2 \
  --revision 607a30d783dfa663caf39e06633721c8d4cfcd7e \
  --require-file config.json --require-file tokenizer.json --require-file model.safetensors
```

4. Require exit `0` **and** `ok: true`. Schema version 1 checks cache, health,
   advertised model and bounded completion in order. Exit `1` fails validation;
   exit `2` is a command syntax error without guaranteed JSON. A false check can
   mean skipped; inspect the first error stage. Preserve the invocation, package
   versions and private startup log. Success does not prove loaded revision,
   GPU use, quality or throughput; an alias alone is not revision attestation.
5. Stop only your own foreground server with Ctrl-C. Confirm exit before releasing
   the allocation. Do not kill another listener or prune the shared cache.

## Stop and recovery

| Observation | Action |
|---|---|
| Missing files or unreadable cache | Stop; designated writer repairs the pinned snapshot, then reader revalidates. Never loosen permissions globally. |
| Full cache | Stop downloads; request operator-reviewed retention, not automatic deletion. |
| Port occupied or endpoint ownership unclear | Stop; identify the owner. Do not validate or kill it without permission. |
| Startup/health failure | Inspect private logs for compatibility, memory and files; rerun validation only after startup is confirmed. |
| Authentication required / HTTP 401 | Stop; use the site's approved authenticated workflow. Never disable controls for this example. |
| Model/completion failure | Compare alias, full file list and server log. Health alone is not success. |
| Multi-node, remote access or production service requested | Stop; unsupported here. Do not widen the bind address or improvise distributed flags. |

Offline fixtures test the validator, not real cache reuse, GPU inference or
agent decision-making. Those require separate verification.
