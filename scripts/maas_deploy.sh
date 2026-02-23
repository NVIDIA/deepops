#!/usr/bin/env bash
# maas_deploy.sh — Deploy, tag, and manage MAAS VMs for testing
#
# Usage:
#   ./scripts/maas_deploy.sh [OPTIONS] [distro_series]
#
# Options:
#   --os <noble|jammy>      Ubuntu series to deploy (default: noble)
#   --profile <k8s|slurm>   Apply MAAS tags for inventory grouping after deploy
#   --tags-only             Just apply/update tags without redeploying
#   --release               Release all VMs back to MAAS
#   --status                Show current VM status and tags
#   -h, --help              Show this help
#
# Configuration:
#   Reads config/maas-inventory.yml (same config as maas_inventory.py).
#   Environment variables override config file values:
#     MAAS_API_URL, MAAS_API_KEY, MAAS_MACHINES, MAAS_SSH_USER,
#     MAAS_SSH_BASTION (or MAAS_SSH_PROXY for full ProxyCommand override)
#
# Examples:
#   ./scripts/maas_deploy.sh --os noble --profile k8s
#   ./scripts/maas_deploy.sh --os jammy --profile slurm
#   ./scripts/maas_deploy.sh --profile k8s --tags-only
#   ./scripts/maas_deploy.sh --status
#   ./scripts/maas_deploy.sh --release
#   ./scripts/maas_deploy.sh noble          # backward compat

set -euo pipefail

# Find repo root (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# MAAS status codes
STATUS_READY=4
STATUS_DEPLOYED=6
STATUS_DEPLOYING=9
STATUS_RELEASING=12

# Known test tags — cleared before applying a profile
KNOWN_TEST_TAGS=(
    kube_control_plane kube_node etcd
    slurm-master slurm-node slurm-nfs slurm-cache slurm-metric slurm-login
)

# --- Configuration ------------------------------------------------------------

load_config() {
    local config_file="${REPO_ROOT}/config/maas-inventory.yml"

    # Parse config file if it exists (simple key: value parsing)
    if [[ -f "$config_file" ]]; then
        local key value line
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ "$line" =~ ^[[:space:]]*$ ]] && continue
            [[ "$line" != *:* ]] && continue

            key="${line%%:*}"
            key="${key// /}"
            value="${line#*:}"
            value="${value#"${value%%[![:space:]]*}"}"  # ltrim
            value="${value%"${value##*[![:space:]]}"}"  # rtrim
            value="${value#\"}" ; value="${value%\"}"    # strip double quotes
            value="${value#\'}" ; value="${value%\'}"    # strip single quotes

            case "$key" in
                api_url)     [[ -z "${MAAS_API_URL:-}" ]]  && MAAS_API_URL="$value" ;;
                api_key)     [[ -z "${MAAS_API_KEY:-}" ]]   && MAAS_API_KEY="$value" ;;
                ssh_user)    [[ -z "${MAAS_SSH_USER:-}" ]]  && MAAS_SSH_USER="$value" ;;
                ssh_bastion) [[ -z "${MAAS_SSH_PROXY:-}" && -z "${MAAS_SSH_BASTION:-}" ]] && MAAS_SSH_BASTION="$value" ;;
                network)     [[ -z "${MAAS_NETWORK:-}" ]]   && MAAS_NETWORK="$value" ;;
                machines)    [[ -z "${MAAS_MACHINES:-}" ]]  && MAAS_MACHINES="$value" ;;
            esac
        done < "$config_file"
    fi

    # Build SSH proxy from MAAS_SSH_BASTION if MAAS_SSH_PROXY not set directly
    if [[ -z "${MAAS_SSH_PROXY:-}" && -n "${MAAS_SSH_BASTION:-}" ]]; then
        MAAS_SSH_PROXY="ssh -W %h:%p -q ${MAAS_SSH_BASTION}"
    fi

    # Defaults for anything still unset
    MAAS_API_URL="${MAAS_API_URL:-}"
    MAAS_API_KEY="${MAAS_API_KEY:-}"
    MAAS_MACHINES="${MAAS_MACHINES:-maas-worker maas-worker-2 maas-worker-3}"
    MAAS_SSH_USER="${MAAS_SSH_USER:-ubuntu}"
    MAAS_SSH_PROXY="${MAAS_SSH_PROXY:-}"
    MAAS_NETWORK="${MAAS_NETWORK:-}"

    # Validate required fields
    if [[ -z "$MAAS_API_URL" ]]; then
        echo "ERROR: MAAS_API_URL not configured"
        echo "Set it in config/maas-inventory.yml or as an environment variable"
        exit 1
    fi
    if [[ -z "$MAAS_API_KEY" ]]; then
        echo "ERROR: MAAS_API_KEY not configured"
        echo "Set it in config/maas-inventory.yml or as an environment variable"
        exit 1
    fi

    # Validate API key format: exactly 3 non-empty colon-separated parts
    if [[ ! "$MAAS_API_KEY" =~ ^[^:]+:[^:]+:[^:]+$ ]]; then
        echo "ERROR: MAAS_API_KEY must be in format consumer_key:token_key:token_secret"
        exit 1
    fi
}

# --- Argument Parsing ---------------------------------------------------------

ACTION="deploy"
DISTRO_SERIES=""
PROFILE=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --os)
                DISTRO_SERIES="$2"; shift 2 ;;
            --profile)
                PROFILE="$2"; shift 2 ;;
            --tags-only)
                ACTION="tags-only"; shift ;;
            --release)
                ACTION="release"; shift ;;
            --status)
                ACTION="status"; shift ;;
            -h|--help)
                # Print header comment as help
                sed -n '2,/^[^#]/{ /^#/s/^# \{0,1\}//p; }' "${BASH_SOURCE[0]}"
                exit 0 ;;
            -*)
                echo "Unknown option: $1"; exit 1 ;;
            *)
                # Backward compat: positional arg is distro series
                DISTRO_SERIES="$1"; shift ;;
        esac
    done

    # Default OS for deploy action
    if [[ "$ACTION" == "deploy" && -z "$DISTRO_SERIES" ]]; then
        DISTRO_SERIES="noble"
    fi

    # Validate: --tags-only requires --profile
    if [[ "$ACTION" == "tags-only" && -z "$PROFILE" ]]; then
        echo "ERROR: --tags-only requires --profile <k8s|slurm>"
        exit 1
    fi

    # Validate profile name if given
    if [[ -n "$PROFILE" && "$PROFILE" != "k8s" && "$PROFILE" != "slurm" ]]; then
        echo "ERROR: Unknown profile '${PROFILE}' (valid: k8s, slurm)"
        exit 1
    fi
}

# --- MAAS API Helpers ---------------------------------------------------------

maas_auth_header() {
    # API key format already validated in load_config()
    local consumer_key token_key token_secret
    IFS=':' read -r consumer_key token_key token_secret <<< "$MAAS_API_KEY"
    local nonce timestamp
    nonce=$(python3 -c "import uuid; print(uuid.uuid4().hex)")
    timestamp=$(date +%s)
    echo "OAuth oauth_version=\"1.0\", oauth_signature_method=\"PLAINTEXT\", oauth_consumer_key=\"${consumer_key}\", oauth_token=\"${token_key}\", oauth_signature=\"&${token_secret}\", oauth_nonce=\"${nonce}\", oauth_timestamp=\"${timestamp}\""
}

maas_get() {
    local endpoint="$1"
    curl -s -H "Authorization: $(maas_auth_header)" "${MAAS_API_URL}${endpoint}"
}

maas_post() {
    local endpoint="$1"
    shift
    curl -s -H "Authorization: $(maas_auth_header)" -X POST "${MAAS_API_URL}${endpoint}" "$@"
}

get_system_id() {
    local hostname="$1"
    maas_get "/machines/?hostname=${hostname}" | python3 -c "
import json, sys
machines = json.load(sys.stdin)
if machines:
    print(machines[0]['system_id'])
else:
    print('', end='')
"
}

get_status() {
    local system_id="$1"
    maas_get "/machines/${system_id}/" | python3 -c "
import json, sys
m = json.load(sys.stdin)
print(m['status'])
"
}

get_ip() {
    local system_id="$1"
    maas_get "/machines/${system_id}/" | MAAS_NETWORK="${MAAS_NETWORK:-}" python3 -c "
import json, os, sys
m = json.load(sys.stdin)
network = os.environ.get('MAAS_NETWORK', '')
for iface in m.get('interface_set', []):
    for link in iface.get('links', []):
        ip = link.get('ip_address', '')
        if network and ip and ip.startswith(network):
            print(ip)
            sys.exit(0)
# Fallback: first IP
for iface in m.get('interface_set', []):
    for link in iface.get('links', []):
        ip = link.get('ip_address', '')
        if ip:
            print(ip)
            sys.exit(0)
"
}

get_machine_info() {
    # Returns: status_name|os_display|tags
    local system_id="$1"
    maas_get "/machines/${system_id}/" | python3 -c "
import json, sys
m = json.load(sys.stdin)
tags = ', '.join(m.get('tag_names', []))
series = m.get('distro_series', '')
series_map = {'noble': '24.04', 'jammy': '22.04', 'focal': '20.04', 'bionic': '18.04'}
if series and m.get('osystem') == 'ubuntu':
    os_info = 'Ubuntu ' + series_map.get(series, series)
elif series:
    os_info = m.get('osystem', '') + '/' + series
else:
    os_info = '-'
print(f'{m.get(\"status_name\", \"Unknown\")}|{os_info}|{tags}')
"
}

wait_for_status() {
    local system_id="$1"
    local target_status="$2"
    local hostname="$3"
    local max_wait=600
    local elapsed=0
    local interval=10

    while [ $elapsed -lt $max_wait ]; do
        local status
        status=$(get_status "$system_id")
        if [ "$status" = "$target_status" ]; then
            return 0
        fi
        printf "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    echo ""
    echo "ERROR: ${hostname} did not reach status ${target_status} within ${max_wait}s (current: ${status})"
    return 1
}

wait_for_ssh() {
    local ip="$1"
    local hostname="$2"
    local max_wait=120
    local elapsed=0
    local ssh_opts=(-o StrictHostKeyChecking=no -o ConnectTimeout=5)

    if [[ -n "$MAAS_SSH_PROXY" ]]; then
        ssh_opts+=(-o "ProxyCommand=${MAAS_SSH_PROXY}")
    fi

    while [ $elapsed -lt $max_wait ]; do
        if ssh "${ssh_opts[@]}" "${MAAS_SSH_USER}@${ip}" "true" 2>/dev/null; then
            return 0
        fi
        printf "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo ""
    echo "ERROR: SSH to ${hostname} (${ip}) not available within ${max_wait}s"
    return 1
}

# --- Tag Management -----------------------------------------------------------

ensure_tag_exists() {
    local tag="$1"
    # Create tag (ignore error if it already exists)
    maas_post "/tags/" -d "name=${tag}" -d "comment=DeepOps test tag" >/dev/null 2>&1 || true
}

add_tag_to_machine() {
    local tag="$1"
    local system_id="$2"
    ensure_tag_exists "$tag"
    maas_post "/tags/${tag}/?op=update_nodes" -d "add=${system_id}" >/dev/null 2>&1
}

remove_tag_from_machine() {
    local tag="$1"
    local system_id="$2"
    maas_post "/tags/${tag}/?op=update_nodes" -d "remove=${system_id}" >/dev/null 2>&1 || true
}

clear_test_tags() {
    echo "  Clearing existing test tags..."
    for tag in "${KNOWN_TEST_TAGS[@]}"; do
        for i in "${!HOSTNAMES[@]}"; do
            remove_tag_from_machine "$tag" "${SIDS[$i]}"
        done
    done
}

do_apply_profile() {
    if [[ -z "$PROFILE" ]]; then
        return 0
    fi

    echo ""
    echo "--- Applying profile: ${PROFILE} ---"

    # Clear existing test tags first (clean slate)
    clear_test_tags

    local idx=0
    for i in "${!HOSTNAMES[@]}"; do
        local hostname="${HOSTNAMES[$i]}"
        local sid="${SIDS[$i]}"
        local tags=""

        case "$PROFILE" in
            k8s)
                if [[ $idx -eq 0 ]]; then
                    tags="kube_control_plane etcd"
                else
                    tags="kube_node"
                fi
                ;;
            slurm)
                if [[ $idx -eq 0 ]]; then
                    tags="slurm-master"
                else
                    tags="slurm-node"
                fi
                ;;
        esac

        echo "  ${hostname} -> ${tags}"
        for tag in $tags; do
            add_tag_to_machine "$tag" "$sid"
        done

        idx=$((idx + 1))
    done
    echo "  Tags applied."
}

# --- Actions ------------------------------------------------------------------

resolve_machines() {
    HOSTNAMES=()
    SIDS=()
    for hostname in $MAAS_MACHINES; do
        local sid
        sid=$(get_system_id "$hostname")
        if [[ -z "$sid" ]]; then
            echo "ERROR: Machine '${hostname}' not found in MAAS"
            exit 1
        fi
        HOSTNAMES+=("$hostname")
        SIDS+=("$sid")
    done
}

do_status() {
    echo "=== MAAS VM Status ==="
    echo ""
    printf "%-18s %-10s %-14s %-16s %s\n" "HOSTNAME" "STATUS" "IP" "OS" "TAGS"
    printf "%-18s %-10s %-14s %-16s %s\n" "--------" "------" "--" "--" "----"

    for i in "${!HOSTNAMES[@]}"; do
        local sid="${SIDS[$i]}"
        local hostname="${HOSTNAMES[$i]}"
        local info ip
        info=$(get_machine_info "$sid")
        ip=$(get_ip "$sid" 2>/dev/null || echo "n/a")

        local status_name os_info tags
        IFS='|' read -r status_name os_info tags <<< "$info"

        printf "%-18s %-10s %-14s %-16s %s\n" \
            "$hostname" "$status_name" "${ip:-n/a}" "$os_info" "$tags"
    done
    echo ""
}

do_release() {
    echo "=== Releasing all machines ==="
    echo ""

    for i in "${!HOSTNAMES[@]}"; do
        local hostname="${HOSTNAMES[$i]}"
        local sid="${SIDS[$i]}"
        local status
        status=$(get_status "$sid")
        if [[ "$status" == "$STATUS_DEPLOYED" ]]; then
            echo "  Releasing ${hostname}..."
            maas_post "/machines/${sid}/" -d "op=release" >/dev/null
        elif [[ "$status" == "$STATUS_READY" ]]; then
            echo "  ${hostname} already ready"
        else
            echo "  ${hostname} status=${status}, attempting release..."
            maas_post "/machines/${sid}/" -d "op=release" >/dev/null 2>&1 || true
        fi
    done

    echo ""
    echo "Waiting for Ready state..."
    for i in "${!HOSTNAMES[@]}"; do
        printf "  Waiting for ${HOSTNAMES[$i]}"
        wait_for_status "${SIDS[$i]}" "$STATUS_READY" "${HOSTNAMES[$i]}"
        echo " Ready"
    done

    echo ""
    echo "All machines released."
}

do_deploy() {
    echo "=== MAAS VM Deploy ==="
    echo "API: ${MAAS_API_URL}"
    echo "Machines: ${MAAS_MACHINES}"
    echo "OS: ${DISTRO_SERIES}"
    [[ -n "$PROFILE" ]] && echo "Profile: ${PROFILE}"
    echo ""

    for i in "${!HOSTNAMES[@]}"; do
        echo "  ${HOSTNAMES[$i]} -> ${SIDS[$i]}"
    done
    echo ""

    # Step 1: Release deployed machines
    echo "--- Step 1: Releasing machines ---"
    for i in "${!HOSTNAMES[@]}"; do
        local hostname="${HOSTNAMES[$i]}"
        local sid="${SIDS[$i]}"
        local status
        status=$(get_status "$sid")
        if [[ "$status" == "$STATUS_DEPLOYED" ]]; then
            echo "  Releasing ${hostname}..."
            maas_post "/machines/${sid}/" -d "op=release" >/dev/null
        elif [[ "$status" == "$STATUS_READY" ]]; then
            echo "  ${hostname} already ready, skipping release"
        else
            echo "  ${hostname} status=${status}, attempting release..."
            maas_post "/machines/${sid}/" -d "op=release" >/dev/null 2>&1 || true
        fi
    done

    # Step 2: Wait for Ready
    echo ""
    echo "--- Step 2: Waiting for Ready state ---"
    for i in "${!HOSTNAMES[@]}"; do
        printf "  Waiting for ${HOSTNAMES[$i]}"
        wait_for_status "${SIDS[$i]}" "$STATUS_READY" "${HOSTNAMES[$i]}"
        echo " Ready"
    done

    # Step 3: Deploy
    echo ""
    echo "--- Step 3: Deploying ${DISTRO_SERIES} ---"
    for i in "${!HOSTNAMES[@]}"; do
        echo "  Deploying ${HOSTNAMES[$i]} with ${DISTRO_SERIES}..."
        maas_post "/machines/${SIDS[$i]}/" -d "op=deploy" -d "distro_series=${DISTRO_SERIES}" >/dev/null
    done

    # Step 4: Wait for Deployed
    echo ""
    echo "--- Step 4: Waiting for deployment (this takes a few minutes) ---"
    for i in "${!HOSTNAMES[@]}"; do
        printf "  Waiting for ${HOSTNAMES[$i]}"
        wait_for_status "${SIDS[$i]}" "$STATUS_DEPLOYED" "${HOSTNAMES[$i]}"
        echo " Deployed"
    done

    # Step 5: Verify SSH
    echo ""
    echo "--- Step 5: Verifying SSH connectivity ---"
    local ssh_opts=(-o StrictHostKeyChecking=no)
    if [[ -n "$MAAS_SSH_PROXY" ]]; then
        ssh_opts+=(-o "ProxyCommand=${MAAS_SSH_PROXY}")
    fi
    for i in "${!HOSTNAMES[@]}"; do
        local ip
        ip=$(get_ip "${SIDS[$i]}")
        printf "  Waiting for SSH on ${HOSTNAMES[$i]} (${ip})"
        wait_for_ssh "$ip" "${HOSTNAMES[$i]}"
        local os_info
        os_info=$(ssh "${ssh_opts[@]}" "${MAAS_SSH_USER}@${ip}" "lsb_release -ds" 2>/dev/null || echo "unknown")
        echo " OK (${os_info})"
    done

    # Step 6: Apply profile tags
    do_apply_profile

    echo ""
    echo "=== All machines deployed and accessible ==="
    echo ""
    echo "You can now run:"
    echo "  source .venv/bin/activate"
    echo "  ansible -m ping all"
    [[ "$PROFILE" == "k8s" ]] && echo "  ansible-playbook playbooks/k8s-cluster.yml"
    [[ "$PROFILE" == "slurm" ]] && echo "  ansible-playbook playbooks/slurm-cluster.yml"
}

# --- Main ---------------------------------------------------------------------

main() {
    parse_args "$@"
    load_config
    resolve_machines

    case "$ACTION" in
        status)    do_status ;;
        release)   do_release ;;
        tags-only) do_apply_profile ;;
        deploy)    do_deploy ;;
    esac
}

main "$@"
