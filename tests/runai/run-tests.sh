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

# 10. exposure: address selection and Gateway API (fake helm/kubectl)
gw() {  # gw <name> <extra ansible args...>
  local name="$1"; shift
  : "${STATE:=$(mktemp -d)}"; export FAKE_STATE="$STATE"
  out="$(ansible-playbook -i localhost, "$HERE/gateway.yml" "$@" 2>&1)"; rc=$?
}
jq_() { python3 -c "import json,sys; d=json.load(open('$STATE/result.json')); print(eval(sys.argv[1]))" "$1"; }
STATE=""; gw lb -e runai_platform_exposure=ingress
[ $rc -eq 0 ] && [ "$(jq_ "d['address']")" = "192.0.2.60" ] && pass "LoadBalancer address is used instead of the node address" || bad "LoadBalancer address ($rc)"
[ "$(jq_ "d['cp']['global'].get('gatewayAPI')")" = "None" ] && pass "ingress exposure leaves Gateway API values out" || bad "ingress values"
unset STATE
STATE=""; FAKE_LB_IP=none gw lb2 -e runai_platform_exposure=ingress
[ $rc -ne 0 ] && echo "$out" | grep -q "No external address" && pass "no LoadBalancer address stops with an explanation" || bad "LB timeout"
unset STATE
STATE=""; gw np -e runai_platform_exposure=ingress -e runai_platform_ingress_service_type=NodePort
[ $rc -eq 0 ] && [ "$(jq_ "d['address']")" = "192.0.2.10" ] && pass "NodePort keeps the node address" || bad "NodePort address"
unset STATE
STATE=""; gw ov -e runai_platform_exposure=ingress -e runai_platform_ingress_ip=198.51.100.7
[ $rc -eq 0 ] && [ "$(jq_ "d['address']")" = "198.51.100.7" ] && pass "explicit address wins" || bad "explicit address"
unset STATE
STATE=""; gw g1 -e runai_platform_exposure=gateway
g1=$rc
[ $g1 -eq 0 ] && [ "$(jq_ "d['address']")" = "192.0.2.50" ] && pass "gateway exposure uses the Gateway address" || bad "gateway address ($g1)"
grep -q "standard-install.yaml" "$STATE/kubectl.log" && grep -q "v1.4.0/standard-install.yaml" "$STATE/kubectl.log" && pass "Gateway API CRDs pinned to v1.4.0" || bad "CRD pin"
python3 - "$STATE" <<'P' && pass "KGateway chart and CRDs pinned to v2.2.1" || bad "kgateway pin"
import json,sys
r=json.load(open(sys.argv[1]+"/releases.json"))
assert r["kgateway-system/kgateway"]["chart"]=="kgateway-v2.2.1" and r["kgateway-system/kgateway-crds"]["chart"]=="kgateway-crds-v2.2.1", r
P
python3 - "$STATE" <<'P' && pass "gateway values: ingress off, Gateway on, path routing" || bad "gateway values"
import json,sys
d=json.load(open(sys.argv[1]+"/result.json"))
g=d["cp"]["global"]; assert g["ingress"]["enabled"] is False and g["gatewayAPI"]["enabled"] is True, g
assert g["gatewayAPI"]["parentRefs"]==[{"name":"runai-gateway","namespace":"runai"}], g
c=d["cluster"]["clusterConfig"]["global"]; assert c["ingress"]["enabled"] is False and c["gatewayAPI"]["name"]=="runai-gateway" and c["subdomainSupport"] is False, c
assert len(d["gateway"]["spec"]["listeners"])==1
P
gw g2 -e runai_platform_exposure=gateway
[ $rc -eq 0 ] && pass "gateway install converges" || bad "gateway rerun"
gw g3 -e runai_platform_exposure=gateway -e runai_test_action=remove
[ $rc -eq 0 ] && [ ! -e "$STATE/gateway" ] && [ ! -e "$STATE/gwcrds" ] && pass "gateway uninstall removes the Gateway and the CRDs it installed" || bad "gateway uninstall ($rc)"
python3 - "$STATE" <<'P' && pass "gateway uninstall removes the controller releases" || bad "controller removal"
import json,sys
assert json.load(open(sys.argv[1]+"/releases.json"))=={}
P
unset STATE
# existing Gateway API CRDs are neither replaced nor removed
STATE="$(mktemp -d)"; echo gateways.gateway.networking.k8s.io > "$STATE/gwcrds"
gw g4 -e runai_platform_exposure=gateway -e runai_gateway_install_controller=false
grep -q "^apply --filename http" "$STATE/kubectl.log" && bad "pre-existing CRDs were re-applied" || pass "pre-existing Gateway API CRDs are left alone"
gw g5 -e runai_platform_exposure=gateway -e runai_gateway_install_controller=false -e runai_test_action=remove
[ -e "$STATE/gwcrds" ] && pass "pre-existing Gateway API CRDs survive uninstall" || bad "foreign CRDs removed"
unset STATE
STATE=""; gw g6 -e runai_platform_exposure=gateway -e runai_gateway_workload_routing=host
python3 - "$STATE" <<'P' && pass "host routing adds the wildcard listener and sub-domain support" || bad "host routing"
import json,sys
d=json.load(open(sys.argv[1]+"/result.json"))
assert len(d["gateway"]["spec"]["listeners"])==2 and d["cluster"]["clusterConfig"]["global"]["subdomainSupport"] is True
P
unset STATE
STATE=""; run bx -e runai_mode=platform -e runai_platform_domain=runai.lab.test -e 'runai_platform_admin_password=Passw0rd!x' -e runai_platform_exposure=bogus
[ $rc -ne 0 ] && pass "unknown exposure refused" || bad "unknown exposure"
unset STATE

# Ownership, foreign users and default absent exercise the real task files.
python3 -m unittest discover -q -s "$HERE" -p "test_gateway_lifecycle.py" && pass "Gateway lifecycle regressions" || bad "Gateway lifecycle regressions"

# Full platform path, including TLS, DNS, registration, rerun and absent.
python3 -m unittest discover -v -s "$HERE" -p "test_gateway_platform.py" && pass "Gateway full platform path" || bad "Gateway full platform path"

# 11. filter unit tests
python3 -m unittest discover -q -s "$HERE" -p "test_runai_helpers.py" && pass "helper unit tests" || bad "helper unit tests"

exit $fail
