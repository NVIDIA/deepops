# Single-node vLLM quickstart

Serve a pinned model from the [shared model cache](shared-cache.md), then check
one completion using a standard-library-only JSON validator. This is an opt-in,
one-GPU example, not a cluster service deployment or performance benchmark. It
uses open-source vLLM and a public model; no paid endpoint or registry entitlement
is needed. Review the model license before use.

## Prerequisites and boundaries

- An approved, otherwise idle Linux GPU allocation with one GPU visible to the
  workload. Respect scheduler allocation and device isolation; do not start this
  in a login shell outside your allocation. Do not override `CUDA_VISIBLE_DEVICES`
  to reach other GPUs. This guide does not allocate resources or install drivers.
- A driver compatible with the selected vLLM wheel's CUDA runtime. The tagged
  v0.31.0 NVIDIA guide describes CUDA 12.9 wheels and compute capability 7.5+.
  Check the upstream installation guide for your GPU/driver before installing;
  a working `nvidia-smi` alone does not establish wheel compatibility.
- Python **3.12** with venv support, available disk space for the serving packages,
  and a fresh private environment separate from both Ansible and the cache writer.
  Python 3.12 lies in both the tagged guide's 3.10–3.13 range and the package's
  broader `>=3.10,<3.15` metadata. This is not a claim that every listed Python
  version or GPU combination has been tested here.
- A fully populated, immutable snapshot from the shared-cache guide. The writer
  downloads `config.json`, `tokenizer.json`, and `model.safetensors` for the GPT-2
  revision below. The serving user must be able to read them. Pause cache writes
  while testing; only trusted operators may write to the cache or its parent.
- Run with the consumer's real UID/group and mount layout. In a container, mount
  the **whole Hub cache** read-only at the same path so relative blob links work.
  Do not mount only `snapshots/`. The reader must not write to the shared cache.
  Keep `HF_HOME`, `HF_TOKEN_PATH`, Xet state, and vLLM's compilation cache private
  on local storage; never copy authentication into the shared cache.
- This demo binds only to loopback. Other local users can still reach the server:
  use an isolated test allocation, no sensitive prompts, and no public exposure.
  Do not change the bind address to share it. Authentication, TLS, remote access,
  production isolation, multi-node serving, and scheduler manifests are outside
  this example. The validator deliberately has no authentication options.

The commands below run **on the allocated serving node**, from the repository
root. Package installation can download large GPU dependencies. For disconnected
systems, prepare an approved wheel mirror first; offline model loading does not
make package installation offline.

## 1. Prepare the private serving environment

```bash
python3.12 -m venv "$HOME/.venvs/deepops-vllm"
"$HOME/.venvs/deepops-vllm/bin/python" -m pip install -r examples/vllm/requirements.txt
"$HOME/.venvs/deepops-vllm/bin/python" -m pip check
"$HOME/.venvs/deepops-vllm/bin/vllm" --version
```

The example pins vLLM **0.31.0**. Transitive packages are not a full lockfile:
record `pip freeze` with validation evidence, and use your site's reviewed wheel
set for repeatable deployment. Do not mix an existing PyTorch installation into
this environment. Do not upgrade the cache writer's pinned CLI to fix a serving
package problem. vLLM loads a local snapshot, not a mutable Hub repository name.

## 2. Check the cache before starting the server

```bash
export HF_HUB_CACHE=/shared/hf-cache/hub
export MODEL_ID=openai-community/gpt2
export MODEL_REVISION=607a30d783dfa663caf39e06633721c8d4cfcd7e
export MODEL_PATH="$HF_HUB_CACHE/models--openai-community--gpt2/snapshots/$MODEL_REVISION"
python3 scripts/validation/validate_model_cache.py --json \
  --cache-dir "$HF_HUB_CACHE" --repo-id "$MODEL_ID" --revision "$MODEL_REVISION" \
  --require-file config.json --require-file tokenizer.json --require-file model.safetensors
```

Stop unless exit status is `0` and `ok` is `true`. For a different model, review
its complete tokenizer/configuration/weight file list, including every indexed
shard. The validator only checks files you name. Never enable remote model code
as a workaround; this example does not use `--trust-remote-code`.

## 3. Serve one GPU in the foreground

In the same allocated shell, start the server and keep its log private:

```bash
HF_HUB_OFFLINE=1 HF_HUB_DISABLE_IMPLICIT_TOKEN=1 \
  "$HOME/.venvs/deepops-vllm/bin/vllm" serve "$MODEL_PATH" \
  --tokenizer "$MODEL_PATH" \
  --served-model-name deepops-gpt2 \
  --host 127.0.0.1 --port 8000 \
  --tensor-parallel-size 1 --dtype half \
  --load-format safetensors --generation-config vllm \
  --max-model-len 512 --max-num-seqs 1 \
  --gpu-memory-utilization 0.5 --enforce-eager
```

Wait for server startup to finish before validating. These conservative settings
bound the demo, not total GPU memory or runtime. Startup can still fail on an
unsupported GPU, unavailable memory, incompatible driver, or incomplete files.
Do not remove scheduler isolation or alter drivers to make this example pass.

`HF_HUB_OFFLINE=1` is scoped to the serving process. It blocks Hub requests but
is not a firewall; use site-enforced egress restrictions when required. Do not
export it globally in clients that need to call a local inference endpoint.
The local model path avoids reader-side Hub downloads and cache updates. Private
framework caches may still be created on the serving node.

This demo expects no server API-key configuration. If site policy requires
authentication, stop and use its approved authenticated client instead; do not
remove site controls to run this validator.

## 4. Validate from another shell on the same node

Use a shell within the same approved allocation and namespace. This makes one
small inference request (up to eight output tokens); it is **not** a read-only
health check and must not be run on someone else's service without permission.

```bash
python3 scripts/validation/validate_vllm.py --json \
  --base-url http://127.0.0.1:8000 --model deepops-gpt2 \
  --cache-dir /shared/hf-cache/hub \
  --repo-id openai-community/gpt2 \
  --revision 607a30d783dfa663caf39e06633721c8d4cfcd7e \
  --require-file config.json --require-file tokenizer.json --require-file model.safetensors
```

It checks, in order:

1. The existing cache validator's immutable revision and file-readability rules.
2. `GET /health` returns HTTP 200.
3. `GET /v1/models` advertises the requested served name.
4. `POST /v1/completions` returns the expected model, nonempty text, and a positive
   count of generated tokens no greater than the eight requested.

GPT-2 is a base text model, so this uses **completions**, not chat or a chat
template. Generated text is intentionally not printed or checked for factual
accuracy. Neither server responses nor error bodies are copied into the result.

### JSON and exit contract

- Exit `0`: all four checks passed and `ok: true`.
- Exit `1`: a validation/input-value failure and `ok: false`.
- Exit `2`: command syntax error (usage on stderr, no JSON promised).
- `--json` writes one JSON object to stdout. Without it, output is a short summary.
- Schema version `1` fields: `schema_version`, `ok`, `checks` (boolean `cache`,
  `health`, `model`, `completion`), `cache` (the cache validator's result or null),
  and `errors` (objects with `stage` and `message`). A false check may be failed
  **or skipped**: execution stops at the first error, whose stage identifies it.
- Only literal loopback HTTP addresses with an explicit port are accepted,
  including `http://[::1]:8000`. No `/v1` suffix, credentials, hostname resolution,
  proxy routing, or redirects. The default is `http://127.0.0.1:8000`.
- No retries. `--timeout` defaults to a 30-second socket timeout (maximum 120),
  with an elapsed-time guard checked between response-body reads. A final blocked
  read can add up to one socket timeout; this is not a hard process deadline.
  CI runners should also impose their own overall command deadline. Each response
  is capped at 1 MiB.

Success proves a small completion from the named local endpoint plus readability
of the listed snapshot files. **It cannot attest that the server loaded that
revision**, used a GPU, avoided all network traffic, or achieved useful quality,
throughput or concurrency. Preserve the server invocation, package versions and
private startup logs for independent verification. An unrelated server using the
same alias is not distinguished by this API check.

Stop only the foreground server you started with Ctrl-C when finished. Confirm
it has exited before releasing the allocation. Do not kill unrelated processes,
prune the shared cache, or remove snapshots that other jobs may use.

## Failure handling

| Failing stage | Action |
|---|---|
| `arguments` | Use a bare loopback origin, served model name and finite timeout. |
| `cache` | Stop; repair missing files as the designated writer or restore the approved mount/reader permissions. Never loosen permissions globally. |
| `health` | Check the private startup log and listening port. Wait for startup, then explicitly rerun once ready. A 401 means use the site's authenticated workflow instead. |
| `model` | Compare `--served-model-name` with `--model`; do not accept a different server/model as success. |
| `completion` | Check the private server log, full file list, model support and available GPU memory. An empty or malformed completion is failure, even when health passed. |

## Development and evidence limits

```bash
python3 -m unittest discover -s scripts/validation/tests -p 'test_vllm.py'
```

Tests use synthetic local HTTP servers and cache files, not vLLM or real weights.
They exercise positive/negative JSON results, request ordering, malformed
responses, timeouts, bounded output, proxy/redirect refusal and cache failures.
They do not certify the pinned serving environment. Real cache reuse, read-only
mounts, offline startup and GPU inference need a separately approved live test.

NVIDIA NIM is an optional alternative, documented by its own
[getting-started guide](https://docs.nvidia.com/nim/large-language-models/latest/getting-started.html).
It is not installed, required, or validated by this example.

## Primary sources (checked 2026-10-05)

- [vLLM 0.31.0 package metadata](https://pypi.org/project/vllm/0.31.0/).
- Tagged [GPU requirements](https://github.com/vllm-project/vllm/blob/v0.31.0/docs/getting_started/installation/gpu.md)
  and [NVIDIA installation details](https://github.com/vllm-project/vllm/blob/v0.31.0/docs/getting_started/installation/gpu.cuda.inc.md).
- Tagged [OpenAI-compatible server guide](https://github.com/vllm-project/vllm/blob/v0.31.0/docs/serving/online_serving/openai_compatible_server.md).
- [Shared-cache sources and writer pin](shared-cache.md#primary-sources-verified-2026-10-05).
