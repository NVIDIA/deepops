# Playground pinned API contracts

These fixtures were checked against upstream tagged source, not inferred from
the deployment template. Tests run offline without installing either server.
They check our boundary requests, not the full servers or GPU compatibility.

## vLLM v0.31.0

`vllm-0.31.0-playground-args.json` is a deliberately small allow-list: every
rendered/exec-time playground option must be present. It does not enumerate all
vLLM options. Adding an option or changing the image version requires reviewing
the corresponding tagged source and updating the fixture. Source URLs and file
SHA-256 hashes are in the fixture.

- `vllm/engine/arg_utils.py`: `EngineArgs.add_cli_args` registers `--model`,
  `--served-model-name`, `--tensor-parallel-size`, `--max-model-len`,
  `--max-num-seqs`, and `--gpu-memory-utilization`.
- `vllm/entrypoints/launchers/cli_args.py`: `FrontendArgs` declares `host` and
  `port`; `BaseFrontendArgs.add_cli_args` translates them to `--host` / `--port`.
- `AsyncEngineArgs` defaults `enable_log_requests=False` and registers
  `--enable-log-requests`; there is no `--disable-log-requests`.
- [Authentication middleware registration](https://github.com/vllm-project/vllm/blob/v0.31.0/vllm/entrypoints/serve/middleware/register.py)
  uses `args.api_key or [envs.VLLM_API_KEY]`. Its SHA-256 is
  `cff2d2c00e16f45a942eb1c1ef591834cb58d34ec9eefb3269f9134c4b1087bf`.
  The entrypoint tests require the private-file key in that environment variable,
  absent from argv. Compose contains neither the key nor the environment value.

## Open WebUI v0.11.4

- [Authentication routes](https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/routers/auths.py):
  `GET /api/v1/auths/` returns the authenticated session's `id`, `email`, `role`.
  Bootstrap checks those fields using the ordinary user's token.
- [Model routes](https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/routers/models.py):
  `ModelAccessGrantsForm` accepts `id` and `access_grants`.
  `POST /api/v1/models/model/access/update` creates a missing base-model record
  only for an admin, replaces grants, and returns the updated `ModelModel`.
  Source SHA-256: `c66d63bfa72d6c24e97ddfd108c396321a8cfd49d7940a10c74c4ceb6d8ed4e6`.
- [Grant schema](https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/models/access_grants.py):
  each input grant uses `principal_type`, `principal_id`, `permission`.
  Bootstrap sends exactly `user`, the authenticated user's ID, and `read`.
  Response grant metadata is allowed, but extra grants/write/wildcard access
  do not satisfy bootstrap's acknowledgment check.
- [Model filtering](https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/utils/models.py):
  `get_filtered_models` and `check_model_access` exclude unregistered models
  for an ordinary user. A base model needs a record and matching read grant.
  Source SHA-256: `04b1a72ee9d5fe4b91e87b0b823292271af69b357fc753762818c859e6fee252`.

### Browser tool-injection regression

- [Chat component](https://github.com/open-webui/open-webui/blob/v0.11.4/src/lib/components/chat/Chat.svelte)
  sends `session_id`, `features` and `tool_servers` to `/api/chat/completions`.
- [Chat handler](https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/main.py)
  moves `session_id` into metadata, defaults function calling to `native`, and
  starts asynchronous socket tasks only when both session and chat IDs exist.
- [Chat middleware](https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/utils/middleware.py)
  sets `use_builtin_tools` for UI sessions unless the model capability
  `builtin_tools` is false (or legacy calling is selected). It converts the
  resolved tools to OpenAI `tools` before forwarding to vLLM, whose default
  tool choice is `auto`. Notes-chat has a separate override, so notes are also
  globally disabled and denied to ordinary users by this role.
- [Built-in tool selection](https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/utils/tools.py)
  includes time, user-input, knowledge and chat-history tools even when code
  execution and web search are disabled. Just disabling those two features
  therefore does not make ordinary browser chat tool-free.
- The model update route above accepts `ModelForm` (`id`, `name`, `meta`,
  `params`, `base_model_id`, `is_active`, `access_grants`). The role keeps the
  named read grant and disables builtins plus executable model capabilities
  every time bootstrap runs. This uses supported model configuration, not a
  patched server or a request filter.

The validator deliberately supplies a session marker without a stored chat ID:
it exercises the UI-only middleware but receives a synchronous JSON response.
It does not simulate the socket stream or prove browser rendering. The HTTP
fake's `auto-tools-unsupported` mode models the old policy's injected tools and
vLLM rejection; it fails only for session-marked requests, so reverting to the
old plain API request breaks the negative test. This is a boundary regression,
not execution of upstream middleware. An actual browser test is still required.

The stateful account fixture starts with no registered model, so the ordinary
user sees none until bootstrap sends a valid admin grant. It covers both fresh
accounts and existing accounts/retries. The HTTP validator fixture separately
requires the ordinary-user token for model discovery and chat and rejects an
admin login before either check. A real server/browser run remains necessary;
these contracts are not a claim of a deployed Open WebUI integration test.
