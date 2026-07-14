# DeepOps skills

Reusable, self-contained procedures for operating DeepOps, written for AI
agents and equally usable by humans. Each skill is a directory containing a
`SKILL.md` with YAML frontmatter (`name`, `description`) followed by
preconditions, exact commands, expected outputs, and failure branches.

The format follows the emerging cross-tool agent-skills convention: agent
frameworks that support skill discovery can load these directly, and any
agent (or person) can simply read the relevant `SKILL.md` before acting.

| Skill | Use when |
|-------|----------|
| [deploy-slurm-cluster](deploy-slurm-cluster/SKILL.md) | Deploying or rebuilding a Slurm GPU cluster. |
| [deploy-k8s-gpu-cluster](deploy-k8s-gpu-cluster/SKILL.md) | Deploying or rebuilding a Kubernetes GPU cluster. |
| [validate-gpu-cluster](validate-gpu-cluster/SKILL.md) | Health checks and post-deploy verification. |
| [diagnose-driver-install](diagnose-driver-install/SKILL.md) | NVIDIA driver failures, `nvidia-smi` errors, GPU pods crash-looping. |

Start with [AGENTS.md](../AGENTS.md) at the repository root for orientation,
golden paths, and operating rules.

Contributions should keep skills honest: every command must work as written
from a clean checkout, and failure branches should come from real observed
failures, not speculation.
