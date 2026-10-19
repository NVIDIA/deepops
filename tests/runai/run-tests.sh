#!/usr/bin/env bash
# Offline tests for roles/runai: fake helm/kubectl, no cluster needed.
# Needs ansible-playbook and python3. Run from anywhere: bash tests/runai/run-tests.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export RUNAI_TEST_BIN="$HERE/bin"
export ANSIBLE_ROLES_PATH="$ROOT/roles"
export ANSIBLE_CONFIG="$ROOT/ansible.cfg"
export ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False
fail=0
pass() { echo "ok   - $1"; }
bad()  { echo "FAIL - $1"; fail=1; }

run() {  # run <name> <extra ansible args...>; sets $out, $rc; fresh state per call unless STATE is set
  local name="$1"; shift
  : "${STATE:=$(mktemp -d)}"; export FAKE_STATE="$STATE"
  out="$(ansible-playbook -i localhost, "$HERE/site.yml" "$@" 2>&1)"; rc=$?
}
changed() { echo "$out" | awk '/PLAY RECAP/{f=1} f && /localhost/' | grep -o 'changed=[0-9]*' | cut -d= -f2; }

# 1. off by default: nothing is installed
STATE=""; run off
[ $rc -eq 0 ] && [ ! -s "$STATE/calls.log" ] && echo "$out" | grep -q "runai_mode is off" && pass "off is a no-op" || bad "off is a no-op"
unset STATE

# 2. bad mode is refused
STATE=""; run badmode -e runai_mode=bogus
[ $rc -ne 0 ] && pass "unknown mode refused" || bad "unknown mode refused"
unset STATE

# 3. kai installs, is pinned, and a rerun changes nothing
STATE=""; run kai1 -e runai_mode=kai
r1=$rc
grep -q -- "--version v0.18.5" "$STATE/calls.log" && grep -q "oci://ghcr.io/kai-scheduler/kai-scheduler/kai-scheduler" "$STATE/calls.log" && pass "kai chart pinned to v0.18.5" || bad "kai chart pinned"
run kai2 -e runai_mode=kai
[ $r1 -eq 0 ] && [ $rc -eq 0 ] && pass "kai converges" || bad "kai converges (rc=$r1/$rc)"
n="$(grep -c '^upgrade' "$STATE/calls.log")"; [ "$n" = "1" ] && pass "kai rerun does not upgrade again (upgrades=$n)" || bad "kai rerun idempotent (upgrades=$n)"
# 3b. fractioning is off unless asked: default sharing mode, no subchart
python3 - "$STATE" <<'P' && pass "kai default keeps gpu-fractioning off" || bad "kai default values"
import json,sys
v=json.load(open(sys.argv[1]+"/releases.json"))["kai-scheduler/kai-scheduler"]["values"]
assert v["global"]["gpuSharingMode"]=="NonMemoryEnforced" and v["global"]["nvFractions"]["set"] is False, v
P
unset STATE

# 4. kai refuses to run beside the Run:ai cluster chart (two KAIs)
export FAKE_STATE="$(mktemp -d)"; echo '{"runai/runai-cluster":{"ns":"runai","chart":"runai-cluster-3.0.20","values":{}}}' > "$FAKE_STATE/releases.json"
STATE="$FAKE_STATE"; run two -e runai_mode=kai
[ $rc -ne 0 ] && echo "$out" | grep -q "ships its own KAI" && pass "kai refused beside runai-cluster" || bad "two-KAI guard (kai)"
unset STATE

# 5. platform refuses when standalone KAI is present
export FAKE_STATE="$(mktemp -d)"; echo '{"kai-scheduler/kai-scheduler":{"ns":"kai-scheduler","chart":"kai-scheduler-v0.18.5","values":{}}}' > "$FAKE_STATE/releases.json"
STATE="$FAKE_STATE"; run two2 -e runai_mode=platform -e runai_platform_domain=runai.lab.test -e 'runai_platform_admin_password=Passw0rd!x'
[ $rc -ne 0 ] && echo "$out" | grep -q "standalone KAI" && pass "platform refused beside standalone KAI" || bad "two-KAI guard (platform)"
unset STATE

# 6. no GPUs: refused with a pointer
STATE=""; FAKE_GPUS=0 run nogpu -e runai_mode=kai
[ $rc -ne 0 ] && echo "$out" | grep -q "No node advertises nvidia.com/gpu" && pass "no GPUs refused" || bad "no GPUs refused"
unset STATE

# 7. fractioning refused on the default driver, and on an old operator
STATE=""; FAKE_DRIVER_MAJOR=580 run frac -e runai_mode=kai -e runai_kai_gpu_fractioning=true
[ $rc -ne 0 ] && echo "$out" | grep -q "GPU Operator" && pass "fractioning refused without GPU Operator v26.7.1" || bad "fractioning operator guard"
unset STATE
export FAKE_STATE="$(mktemp -d)"; echo '{"gpu-operator/nvidia-gpu-operator":{"ns":"gpu-operator","chart":"gpu-operator-v26.7.1","values":{}}}' > "$FAKE_STATE/releases.json"
STATE="$FAKE_STATE"; FAKE_DRIVER_MAJOR=580 run frac2 -e runai_mode=kai -e runai_kai_gpu_fractioning=true
[ $rc -ne 0 ] && echo "$out" | grep -q "r615" && pass "fractioning refused on driver r580" || bad "fractioning driver guard"
FAKE_DRIVER_MAJOR=615 run frac3 -e runai_mode=kai -e runai_kai_gpu_fractioning=true
[ $rc -eq 0 ] && pass "fractioning accepted with v26.7.1 + r615" || bad "fractioning accepted ($rc)"
python3 - "$STATE" <<'P' && pass "fractioning sets NvFractions" || bad "fractioning values"
import json,sys
v=json.load(open(sys.argv[1]+"/releases.json"))["kai-scheduler/kai-scheduler"]["values"]
assert v["global"]["gpuSharingMode"]=="NvFractions" and v["global"]["nvFractions"]["set"] is True, v
P
unset STATE

# 8. uninstall removes every release it owns
STATE=""; run u1 -e runai_mode=kai
run u2 -e runai_state=absent
python3 - "$STATE" <<'P' && pass "uninstall leaves no releases" || bad "uninstall leaves releases"
import json,sys
assert json.load(open(sys.argv[1]+"/releases.json"))=={}
P
unset STATE

# 9. platform input checks (no secrets needed to see them fail)
STATE=""; run p1 -e runai_mode=platform
[ $rc -ne 0 ] && echo "$out" | grep -q "runai_platform_domain" && pass "platform needs a domain" || bad "platform domain check"
run p2 -e runai_mode=platform -e runai_platform_domain=runai.lab.test -e runai_platform_admin_password=weak
[ $rc -ne 0 ] && pass "platform refuses a weak admin login" || bad "weak login"
echo "$out" | grep -q "weak" && bad "login value leaked into output" || pass "login value not printed"
unset STATE

# 10. filter unit tests
python3 -m unittest discover -q -s "$HERE" -p "test_runai_helpers.py" && pass "helper unit tests" || bad "helper unit tests"

exit $fail
