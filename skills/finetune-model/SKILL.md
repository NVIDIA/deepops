---
name: finetune-model
description: Use when checking whether one DeepOps Slurm GPU node is prepared for fine-tuning, diagnosing missing cached training inputs or container prerequisites, or distinguishing readiness from actual training success.
---

# Check fine-tuning readiness

This skill checks preparation only. It provides **no training recipe**. A
`ready` result always has `training_validated: false`. Multi-node training is
unsupported here; do not invent a distributed command or report a successful
fine-tune from this check.

## Preconditions

- Read the [readiness guide](../../docs/model-workflows/finetune-readiness.md).
  Run from the repository root as the intended model consumer on the selected
  compute host, not the login node. The validator checks local host identity
  against the scheduler record; do not bypass a mismatch.
- Obtain authorization for the target and read-only scheduler queries. Specify
  one node and one partition. An IDLE node with an unallocated GPU is required;
  this conservative check does not accept mixed, draining or flagged nodes.
- Follow [manage-model-cache](../manage-model-cache/SKILL.md) for an approved
  shared cache, immutable revision and complete reviewed required-file list.
  Supported inputs are Hugging Face `tokenizer.json` plus safetensors weights;
  list every extra model-specific asset. Indexed weights require every shard.
- Select a site-reviewed fine-tuning image pinned by digest, using Pyxis syntax
  `registry#repository@sha256:<digest>`. Do not use mutable tags, credentials in
  the reference, or substitute an unreviewed image to get a pass.

## Readiness check

Set the variables to reviewed values. For sharded weights, replace the final
file argument with `model.safetensors.index.json`; the validator follows its
weight map. Add every additional file needed by the selected model.

```bash
python3 scripts/validation/validate_finetune.py --json \
  --node "$NODE" --partition "$PARTITION" \
  --container-image "$TRAINING_IMAGE" \
  --cache-dir "$HF_HUB_CACHE" --repo-id "$MODEL_REPO" --revision "$MODEL_REVISION" \
  --require-file config.json --require-file tokenizer.json \
  --require-file tokenizer_config.json --require-file model.safetensors
```

| Result | Next action |
|---|---|
| Exit `0`, `status: ready`, `ok: true` | Report readiness only, including that container execution and training remain unproven. |
| Exit `1`, `status: not_ready` | Report every `errors[]` stage. Repair the named prerequisite through its approved procedure; do not drain nodes, install software or download models implicitly. |
| Exit `2`, `status: bad_input` | Correct explicit inputs or unsupported flags using `--help`. No scheduler commands run for bad input. |

## Optional one-GPU probe

Off by default. Only with explicit authorization to allocate a GPU and run the
reviewed image, repeat the command with `--gpu-smoke`. This can download the
container image and submits one bounded, single-node, single-GPU `nvidia-smi`
job after all readiness gates pass. It does not load the model or train.
`gpu_smoke_ok: true` proves only the container GPU probe, not cache access
inside the container, framework compatibility, learning or checkpoint recovery.

Keep credentials private, mount shared inputs read-only in any future reviewed
recipe, and keep outputs/checkpoints outside the input cache. A readable cache,
a pinned image string, and a GPU probe cannot certify a training outcome.
