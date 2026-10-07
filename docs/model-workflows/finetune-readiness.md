# Single-node fine-tuning readiness

This is a **preparation check, not a training recipe**. It never reports training
success. Run `scripts/validation/validate_finetune.py` as the intended consumer
on the selected Slurm compute host, with the shared cache mounted there. It
uses Python's standard library and the existing local cache validator.

## Supported boundary

- One explicitly named Slurm node and partition. `scontrol show node` must
  report the local hostname as `NodeHostName`; aliases not matching the local
  hostname or its short form fail closed. The partition must be UP and include
  the node. Node names cannot be ranges, lists or command options.
- The node must be exactly IDLE, with at least one configured GPU and zero
  allocated GPUs. Mixed, drained, powered-down and flagged states do not pass.
  This is a point-in-time check, not a reservation or promise that a job will
  schedule; accounts, reservations, memory, licenses and job policy can still
  prevent an allocation.
- Local `enroot version` and Pyxis options in `srun --help` must be available.
  These prove installation/advertisement only, not that a container executes.
  The optional probe below tests that narrower runtime outcome.
- The image reference must be `registry#repository@sha256:<64 lowercase hex
  digits>`. A version tag alone is not immutable. The validator does not fetch
  an image or verify its framework compatibility, contents, trust or registry
  accessibility. The operator must choose a reviewed fine-tuning image.
- Supported cache layout: `config.json`, `tokenizer_config.json`,
  `tokenizer.json`, and either `model.safetensors` or
  `model.safetensors.index.json` with a nonempty `weight_map`. Every indexed
  shard must exist, be nonempty, and resolve within the cache. Weight indexes
  larger than 8 MiB fail closed. The explicit required-file list must include
  all other assets required by the chosen model (for example custom config or
  tokenizer assets). Other weight/tokenizer layouts need a reviewed recipe;
  do not claim unsupported models are ready by dropping required files.

File checks prove readable named inputs and complete indexed shards, not hashes,
valid model contents, license rights or successful loading. The required-file
list is supplied by the operator, not inferred as a guarantee of every model's
requirements. No model code is imported. Keep cache credentials private and
outputs separate from the read-only input cache.

## Default: no workload submitted

Set these variables to site-approved values. Do not paste credentials into
commands. Choose the full immutable model commit, the full image digest and the
complete model file list before running:

```bash
python3 scripts/validation/validate_finetune.py --json \
  --node "$NODE" --partition "$PARTITION" \
  --container-image "$TRAINING_IMAGE" \
  --cache-dir "$HF_HUB_CACHE" --repo-id "$MODEL_REPO" --revision "$MODEL_REVISION" \
  --require-file config.json --require-file tokenizer.json \
  --require-file tokenizer_config.json --require-file model.safetensors
```

For sharded models replace `--require-file model.safetensors` with
`--require-file model.safetensors.index.json`; shard paths are read from the
validated local index. Repeat `--require-file` for additional assets. The
validator does not warm the cache, install anything, start a container or submit
a job by default. It only runs the read-only scheduler and local capability
queries described above. Every external command has a per-command timeout
(default 30 seconds, maximum 120); this is not a whole-invocation time budget.

## Optional GPU container probe

With separate authorization for the exact target and reviewed image, append
`--gpu-smoke`. Only after **all** readiness checks pass, it runs:

```text
srun --nodes=1 --ntasks=1 --gpus=1 --immediate=5 --time=1 \
  --nodelist=<node> --partition=<partition> --container-image=<pinned-image> \
  nvidia-smi --query-gpu=index,name --format=csv,noheader
```

This may pull the container image. The allocation has a one-minute scheduler
time limit and a five-second immediate-allocation limit; the local command has
the configured timeout. A slow image pull can make the probe fail. Confirm job
termination through the site's normal procedure after a timeout; do not blindly
retry. Require a zero exit and exactly one GPU row. No training, dataset loading,
model loading or shared-cache mounting is performed by this probe. In particular,
it cannot attest cache permissions inside a future training container.

## JSON contract (schema version 1)

| Field | Meaning |
|---|---|
| `status` | `ready`, `not_ready`, or `bad_input`. |
| `ok` | True only when all requested readiness/probe checks pass. |
| `training_validated` | Always false, including after the optional probe. |
| `checks` | Booleans for `scheduler`, `local_node`, `gpu_capacity`, `container_support`, `cache`, `container_pin`. |
| `errors` | One object per failed check: stable `stage` plus safe `message`. Multiple independent failures are retained. |
| `gpu_smoke_ran` | Whether the optional allocation command was attempted. False by default and after any failed preflight. |
| `gpu_smoke_ok` | Whether the requested container GPU probe passed. False if skipped. |

Exit `0` means ready; `1` means not ready; `2` means bad input. Missing and
unknown CLI arguments also produce `bad_input` JSON when `--json` is supplied.
Bad inputs run no scheduler or container commands. Multi-node options are not
supported and fail as bad input. `--help` prints ordinary usage text.
Raw scheduler/runtime output, image credentials and generated text are not
included in results. Before sharing results externally, still check them against
your site's data policy.

A successful fine-tuning recipe would require separate evidence of completed
training, improving loss, checkpoint reload and inference from the tuned model.
None is supplied or asserted by this readiness tool.

## Offline tests

```bash
python3 -m unittest discover -s scripts/validation/tests -v
```

The fixtures use temporary model files and inert command boundaries/executables.
They cover successful readiness, each failed prerequisite, aggregated failures,
malformed inputs, incomplete or escaping cache paths, indexed weights, JSON/exit
codes, and optional probe bounds. They do not run on or certify live hardware.
See [the fine-tuning skill](../../skills/finetune-model/SKILL.md) for agent routing
and [the cache guide](shared-cache.md) for cache setup and permissions.
