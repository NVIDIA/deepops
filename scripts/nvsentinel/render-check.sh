#!/usr/bin/env bash
# Offline render check for the NVSentinel values template. No cluster needed.
# Usage: NVSENTINEL_CHART=/path/to/nvsentinel-v1.27.0.tgz scripts/nvsentinel/render-check.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export NVSENTINEL_TEMPLATE="${here}/../../roles/nvsentinel/templates/values.yaml.j2"
export NVSENTINEL_CHART="${NVSENTINEL_CHART:-${HOME}/.cache/helm/repository/nvsentinel-v1.27.0.tgz}"
[ -f "$NVSENTINEL_CHART" ] || { echo "chart not found: $NVSENTINEL_CHART (helm pull oci://ghcr.io/nvidia/nvsentinel --version v1.27.0)"; exit 2; }
command -v helm >/dev/null || { echo "helm not found"; exit 2; }
exec python3 "${here}/render_check.py"
