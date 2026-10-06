---
name: model-workflows
description: Use when choosing a DeepOps model workflow, combining shared model caching with single-node serving, or determining whether a fine-tuning or multi-node request has a supported procedure.
---

# Choose a model workflow

This is the umbrella entry point, not a launcher. Start from the repository
root. Identify the requested outcome before running anything: cached inputs,
working inference, or training are different outcomes with different evidence.

## Select the supported path

| Requested outcome | Procedure | Evidence |
|---|---|---|
| Prepare or repair shared model inputs | [Manage model cache](../manage-model-cache/SKILL.md) | Cache validator exit `0` and `ok: true`, as the real consumer. Only named-file readability is proven. |
| Serve a pinned snapshot on one GPU | [Serve model](../serve-model/SKILL.md) | Cache gate first, then serving validator exit `0` and `ok: true`. One bounded completion, not training or performance validation. |
| Check fine-tuning prerequisites | [Fine-tuning readiness](../finetune-model/SKILL.md) | Readiness validator exit `0`, `status: ready`, `training_validated: false`. Optional one-GPU container probe is off by default. |
| Actually fine-tune a model | Stop: no supported training recipe or training-result validator is provided here yet. | Readiness is not training success. Obtain a reviewed recipe and explicit success criteria before proceeding. |
| Multi-node serving or training | Stop: unsupported by these skills. | Do not infer distributed support from a successful single-node check. |

## Common preflight

1. Confirm the operator's goal, model license, repository ID, immutable full
   revision, complete required-file list, cache path and real reader UID/group.
   Do not accept a directory or `config.json` alone as complete model coverage.
2. Confirm the target and authorization for each action. Cache preparation,
   downloads, package installation, GPU allocation, service startup and inference
   requests are separate actions. A skill or validator grants none of them.
3. Reuse the existing cache interface: share only `HF_HUB_CACHE`, use a designated
   writer and pass the local snapshot path to consumers. Mount the whole cache
   read-only; keep authentication and framework caches private. Never put training
   outputs or checkpoints in the shared input cache.
4. Follow the selected skill's failure branches. Stop on absent authorization,
   incomplete files, space pressure, unknown endpoint ownership or required site
   authentication. Never remove controls, change infrastructure or delete other
   users' files to turn a failure into a pass.

## Report only the evidence obtained

Record which validator ran, its exit code, schema version, explicit inputs and
checks. The [cache guide](../../docs/model-workflows/shared-cache.md) and
[serving guide](../../docs/model-workflows/vllm-quickstart.md) define their JSON
contracts; the [fine-tuning readiness guide](../../docs/model-workflows/finetune-readiness.md)
separates preparation from training. This umbrella does not invent a combined
success field.

A readable cache is preparation only. A completion is inference only. Neither
proves that a particular revision was loaded, a GPU was used, or training
succeeded. A checkpoint filename by itself is not training validation. Keep
startup logs private; do not include credentials or sensitive prompts in reports.
No multi-node hooks or implicit fallback to a different workflow are provided.
