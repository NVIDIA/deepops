# Private single-GPU model playground

An **opt-in, experimental** browser chat on one Ubuntu GPU host: Open WebUI talks
only to a local vLLM server. This is not imported into the Slurm or Kubernetes
playbooks. Offline tests are not evidence of a successful GPU deployment.

## Prerequisites and boundaries

- Exactly one dedicated Ubuntu 22.04 or 24.04 x86_64 host with one GPU. Budget for
  the model, 8K context and runtime overhead; an 80 GB GPU has ample headroom for
  the default. No shared storage or NFS is required.
- Run the existing DeepOps [driver setup](../../skills/diagnose-driver-install/SKILL.md)
  and `playbooks/container/nvidia-docker.yml` first. The role **does not install,
  reconfigure, upgrade or remove the GPU driver or container toolkit**. Use a
  driver compatible with the pinned container's CUDA version; Blackwell requires
  the appropriate open kernel modules. Verify a GPU container first.
- Docker Engine with the NVIDIA runtime and the **Docker Compose v2 plugin** must
  already work. The role checks these prerequisites and exactly one GPU.
- Controller: normal DeepOps Ansible setup and an explicitly reviewed inventory.
  The role installs only `python3-venv` and `openssl` host prerequisites.
- Initial installation needs outbound access for Ubuntu packages, PyPI, public
  container registries and public, ungated model files. **Do not supply an HF
  token.** Model downloads run in a private venv using `huggingface_hub==2.1.1`,
  with an empty inherited environment and implicit token use disabled.
- All owned files live under `/var/lib/deepops/model-playground`, root-only. Do
  not put other workloads, mount points, symlinks or valuable data there.
  Cleanup deletes this entire tree, including chats and model weights.

## Model and image pins

The default `playground_model_profile: qwen3` selects:

- `Qwen/Qwen3-8B` at `b968826d9c46dd6066d109eabc6255188de91218`.
- Served name: `local-qwen3-8b`.

`playground_model_profile: gpt-oss` selects the alternative:

- `openai/gpt-oss-20b` at `6cee5e81ee83917806bbde320786a8fb61efebee`.
- Served name: `local-gpt-oss-20b`.

**Why Qwen is the default:** vLLM's tagged 0.31.0 supported-model table lists
GPT-OSS, and the upstream GPT-OSS recipe explicitly covers H100/Hopper. However,
the tagged GPU and quantization documentation reviewed on 2026-10-07 did not
establish GPT-OSS MXFP4 support specifically on RTX PRO 6000 (Blackwell).
Generic Blackwell/B200 guidance is not proof for that GPU. This is a conservative
fallback, **not a claim that GPT-OSS cannot run there**. Select GPT-OSS only after
checking the actual GPU/kernel combination. Neither profile is hardware-certified
by the offline tests in this change.

Sources:

- [vLLM 0.31.0 supported models](https://github.com/vllm-project/vllm/blob/v0.31.0/docs/models/supported_models.md)
- [vLLM 0.31.0 NVIDIA requirements](https://github.com/vllm-project/vllm/blob/v0.31.0/docs/getting_started/installation/gpu.cuda.inc.md)
- [vLLM 0.31.0 quantization support](https://github.com/vllm-project/vllm/blob/v0.31.0/docs/features/quantization/README.md)
- [Upstream GPT-OSS recipe](https://github.com/vllm-project/recipes/blob/main/OpenAI/GPT-OSS.md)
  (rolling guidance, not a version-pinned compatibility certification).

The role pins manifest-list digests resolved from the registries on 2026-10-07:

| Component | Version | SHA-256 digest |
|---|---|---|
| vLLM | `vllm/vllm-openai:v0.31.0` | `c1c9f6fd5c109ba7f0546a59f5b2f15fb87f64c77782e90a27b648b42a8e67c3` |
| Open WebUI | `ghcr.io/open-webui/open-webui:v0.11.4` | `9591b13f13843c7721c2b8eaf7382846c81b3ffe126526d1888d1fed50c6a33f` |
| HTTPS gateway | `nginx:1.28.0-alpine` | `30f1c0d78e0ad60901648be663a710bdadf19e4c10ac6782c235200619158284` |

The complete model identity is recorded in `model.json` on the host. The existing
`validate_model_cache.py` checks every required configuration, tokenizer, index
and weight-shard file before starting containers. The cache is a local Hub-layout
cache, mounted **read-only** at `/models`. This validates presence, containment
and readability, not cryptographic integrity of every weight file.

## Reproduce

Use a dedicated inventory group with one host; do not use `all`:

```ini
[model-playground]
playground ansible_host=gpu.example.org ansible_user=ubuntu
```

Put non-secret overrides in the inventory's group variables:

```yaml
playground_enabled: true
playground_user_name: Reader
playground_user_email: reader@example.org
playground_admin_email: admin@example.org
playground_model_profile: qwen3
playground_bind_address: "127.0.0.1"
playground_https_port: 8443
playground_tls_name: localhost
```

```bash
ansible-inventory -i config/inventory --graph
ansible-playbook -i config/inventory -l playground playbooks/model-playground.yml
```

This downloads only the selected snapshot files, creates stable random secrets
**on the host**, starts private services, provisions an administrator and the
named ordinary user, and requires a real user chat before starting the HTTPS
listener. A rerun reuses credentials, UI data and model files. It reconciles
containers and briefly stops the listener while rechecking accounts and inference;
this is not a zero-downtime operation. Never run concurrent deployments.

Both inference containers have only an internal Docker network: **no published
vLLM or plain-HTTP UI port and no external network route**. Only the HTTPS gateway
joins the frontend network. vLLM has `HF_HUB_OFFLINE=1` and API-key authentication.
Open WebUI requires login, denies self-registration, disables Ollama, web search,
image generation, direct/user connections, code execution, community sharing and
telemetry. Its sole model connection is `http://vllm:8000/v1`. Persistent UI
configuration is disabled so saved connection settings do not override the role
at restart. The gateway blocks registration and restricts browser connections to
the same origin. Administrators and Docker/root access remain trusted privileges.

Container logging is deliberately disabled: startup arguments, authentication
responses and chat text must not enter Docker logs. Secret-reading Ansible tasks
use `no_log`; passwords and API keys are not templated into Compose or returned
to the controller. Runtime processes necessarily hold secrets; a root/Docker
administrator can inspect them. This is not multi-tenant isolation against host
administrators.

## HTTPS access

Default: loopback binding with an SSH tunnel:

```bash
ssh -N -L 8443:127.0.0.1:8443 ubuntu@gpu.example.org
```

Open `https://localhost:8443`. The role creates a self-signed 30-day certificate.
Retrieve its **public** `tls/cert.pem` over the already trusted SSH connection and
trust it in a dedicated browser profile/OS trust store according to site policy.
Do not disable certificate verification or blindly accept an unknown certificate.
No private key leaves the host. Changing certificate identity or renewing it
requires a deliberate certificate replacement (or cleanup/redeploy).

For access through a private network, change only the variables:
`playground_bind_address` to the host's private IPv4 address and
`playground_tls_name` to its matching DNS name. Keep access limited with site
firewall/network controls; this role does not configure them. Do not bind a
public address. The bind setting is not an access-control policy. Set the
certificate name before first deployment; changing it does not silently rotate
an existing certificate. Use that same name in the browser so certificate and
origin checks agree.

## Retrieve credentials privately

The ordinary user's login is in `secrets/user.json`; the administrator's login
is separately in `secrets/admin.json`. Never use the administrator for ordinary
chat or the end-to-end test. Never place passwords, keys, generated replies or
these JSON files in an issue, Ansible variables, terminal transcript or Git.

On the operator's own trusted machine, retrieve the ordinary-user file directly
into private local storage, **not terminal output**:

```bash
umask 077
mkdir -p "$HOME/.local/share/model-playground-login"
ssh ubuntu@gpu.example.org \
  'sudo -n cat /var/lib/deepops/model-playground/secrets/user.json' \
  > "$HOME/.local/share/model-playground-login/user.json"
chmod 600 "$HOME/.local/share/model-playground-login/user.json"
```

This assumes approved noninteractive sudo; otherwise use the site's approved
private retrieval procedure. Open the private file with a trusted password
manager/local editor, enter credentials only in the verified HTTPS login page,
and remove the local copy when no longer needed. Do not paste credentials into
chat, tickets, commands or shared documents. Do not retrieve the backend API key
for normal browser use.

## Validate, restart, cleanup

On the GPU host, run the validator **inside WebUI's private network** using the
served name, repository and revision recorded in `model.json`:

```bash
sudo docker compose --project-name deepops-playground \
  --file /var/lib/deepops/model-playground/compose.yml exec -T webui \
  python3 /opt/playground/validate_playground.py --json \
  --model local-qwen3-8b --repo-id Qwen/Qwen3-8B \
  --revision b968826d9c46dd6066d109eabc6255188de91218 \
  --user-file /run/playground/user.json --api-key-file /run/playground/api-key
```

Success is exit zero and `"ok": true`, with login, backend identity, UI model list
and chat checks all true. It logs in as the ordinary user, requires exactly one
model from both APIs, compares vLLM's `root` to the exact pinned `/models/...`
snapshot, and demands nonempty assistant content from a chat through WebUI.
Health alone, reasoning-only content, extra/cloud models and wrong snapshots
fail. JSON never includes the reply, password, session token or API key. The
validator supports verified HTTPS via `--webui-url` and `--ca-file` where that
endpoint and the private backend are both reachable; it never disables TLS,
follows redirects or inherits proxy routing.

After deployment, separately test browser login, a real streamed chat and HTTPS
trust. The internal API validator is not a browser, GPU performance test or
proof of external reachability. After a failure, inspect container state without
printing process environments or arguments. GPU readiness can take several
minutes; inference retries are bounded. A failed initial validation leaves the
HTTPS listener closed.

```bash
# Restart only: no model download, secret rotation, or driver work.
ansible-playbook -i config/inventory -l playground playbooks/model-playground.yml --tags restart

# Destructive: deletes all playground containers, networks, volumes/bind data,
# model cache, private venv, chats, secrets and certificates. Leaves driver,
# toolkit, Docker, package prerequisites and cached images alone.
ansible-playbook -i config/inventory -l playground playbooks/model-playground.yml --tags cleanup
```

Do not combine lifecycle tags. Rerun the validator after restart; a container
starting is not inference evidence. `unless-stopped` restores services after a
host reboot, but a manually stopped service stays stopped. Cleanup is repeatable;
redeploy afterward generates new passwords and a new certificate. Use cleanup
before changing account identities. Changing profiles requires a deployment
rerun and a fresh validator run; old model cache files remain until cleanup.

Try: “Explain tensor parallelism with a short analogy,” “Write a Python function
that checks a list for duplicates,” or “Compare two approaches to organizing my
study notes.” Do not submit secrets or sensitive data during a trial.

## Offline development checks

```bash
python3 -m unittest discover -s scripts/validation/tests -p 'test_*.py'
ansible-playbook -i 'localhost,' --syntax-check playbooks/model-playground.yml
./scripts/deepops/ansible-lint-roles.sh
git diff --check
```

The fake-server tests include cloud/extra model lists, wrong roots, empty replies,
health-only services, wrong account roles, invalid JSON, redirects, oversized
responses, private file permissions and proxy isolation. Template tests cover
published ports, read-only mounts, offline settings, auth and restart policy.
No test downloads weights, starts containers or uses a GPU.
