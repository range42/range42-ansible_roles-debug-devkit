#!/bin/bash

#
# Tests for devkit_manifest.find_*.sh lookup tools.
#
# Self-contained: builds a temporary scenario tree with a fixture manifest,
# then invokes each tool and asserts the output. No Proxmox API needed.
#

set -euo pipefail
IFS=$'\n\t'

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS  $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL  $label"
    echo "        expected: $expected"
    echo "        actual:   $actual"
    FAIL=$((FAIL+1))
  fi
}

assert_exit_nonzero() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  FAIL  $label (expected non-zero exit, got 0)"
    FAIL=$((FAIL+1))
  else
    echo "  PASS  $label"
    PASS=$((PASS+1))
  fi
}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# Fixture setup
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scenarios/test_scenario/manifest"
mkdir -p "$TMP/scenarios/test_scenario/01_admin/stage_01/test_admin_wazuh.devkit"

cat >"$TMP/scenarios/test_scenario/manifest/scenario_vms.json" <<'JSON'
{
  "scenario": "test_scenario",
  "version": 2,
  "description": "fixture for devkit_manifest lookup tests",
  "vms": [
    {"vm_id": 2120, "vm_name": "test-admin-wazuh",   "ip": "192.168.142.120", "role": "admin", "bridge": "vmbr142"},
    {"vm_id": 2121, "vm_name": "test-admin-gateway", "ip": "192.168.142.121", "role": "admin", "bridge": "vmbr142"},
    {"vm_id": 2200, "vm_name": "test-team-01",       "ip": "192.168.143.200", "role": "team",  "bridge": "vmbr143"},
    {"vm_id": 2201, "vm_name": "test-team-02",       "ip": "192.168.143.201", "role": "team",  "bridge": "vmbr143"}
  ],
  "templates": []
}
JSON

CALLER="$TMP/scenarios/test_scenario/01_admin/stage_01/test_admin_wazuh.devkit/some.sh"
touch "$CALLER"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# Tests
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

echo "== devkit_manifest.find_vm_id.to.text.sh =="
assert_eq "find_vm_id wazuh"   "2120" "$(devkit_manifest.find_vm_id.to.text.sh "$CALLER" test-admin-wazuh)"
assert_eq "find_vm_id gateway" "2121" "$(devkit_manifest.find_vm_id.to.text.sh "$CALLER" test-admin-gateway)"
assert_eq "find_vm_id team01"  "2200" "$(devkit_manifest.find_vm_id.to.text.sh "$CALLER" test-team-01)"
assert_exit_nonzero "find_vm_id unknown vm_name -> exit 1" \
  devkit_manifest.find_vm_id.to.text.sh "$CALLER" does-not-exist
assert_exit_nonzero "find_vm_id no manifest in tree -> exit 1" \
  devkit_manifest.find_vm_id.to.text.sh "/tmp/no_such_path/some.sh" test-admin-wazuh

echo "== devkit_manifest.find_vm_ip.to.text.sh =="
assert_eq "find_vm_ip wazuh"   "192.168.142.120" "$(devkit_manifest.find_vm_ip.to.text.sh "$CALLER" test-admin-wazuh)"
assert_eq "find_vm_ip team02"  "192.168.143.201" "$(devkit_manifest.find_vm_ip.to.text.sh "$CALLER" test-team-02)"
assert_exit_nonzero "find_vm_ip unknown -> exit 1" \
  devkit_manifest.find_vm_ip.to.text.sh "$CALLER" nope

echo "== devkit_manifest.find_ips_by_role.to.text.sh =="
admin_ips=$(devkit_manifest.find_ips_by_role.to.text.sh "$CALLER" admin)
expected_admin="192.168.142.120 # test-admin-wazuh
192.168.142.121 # test-admin-gateway"
assert_eq "ips_by_role admin" "$expected_admin" "$admin_ips"

team_ips=$(devkit_manifest.find_ips_by_role.to.text.sh "$CALLER" team)
expected_team="192.168.143.200 # test-team-01
192.168.143.201 # test-team-02"
assert_eq "ips_by_role team" "$expected_team" "$team_ips"

assert_eq "ips_by_role unknown role -> empty" "" \
  "$(devkit_manifest.find_ips_by_role.to.text.sh "$CALLER" nonexistent_role)"

echo "== devkit_manifest.find_vms_by_role.to.jsons.sh =="
admin_jsons=$(devkit_manifest.find_vms_by_role.to.jsons.sh "$CALLER" admin)
admin_count=$(echo "$admin_jsons" | wc -l)
assert_eq "vms_by_role admin count" "2" "$admin_count"
first_vm_id=$(echo "$admin_jsons" | head -1 | jq -r .vm_id)
assert_eq "vms_by_role admin first vm_id" "2120" "$first_vm_id"

echo "== devkit_manifest.find_ips_by_bridge.to.text.sh =="
br142=$(devkit_manifest.find_ips_by_bridge.to.text.sh "$CALLER" vmbr142)
expected_br142="192.168.142.120 # test-admin-wazuh
192.168.142.121 # test-admin-gateway"
assert_eq "ips_by_bridge vmbr142" "$expected_br142" "$br142"

br143=$(devkit_manifest.find_ips_by_bridge.to.text.sh "$CALLER" vmbr143)
expected_br143="192.168.143.200 # test-team-01
192.168.143.201 # test-team-02"
assert_eq "ips_by_bridge vmbr143" "$expected_br143" "$br143"

echo "== devkit_manifest.find_vms_by_bridge.to.jsons.sh =="
br142_jsons=$(devkit_manifest.find_vms_by_bridge.to.jsons.sh "$CALLER" vmbr142)
br142_count=$(echo "$br142_jsons" | wc -l)
assert_eq "vms_by_bridge vmbr142 count" "2" "$br142_count"

echo ""
echo "== Summary =="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
