#!/bin/bash

#
# Tests for the SDN network chain : create / attach / NAT on-off-on / delete.
#
# This is section 9 of the SDN plan turned into code, which is task T-12. Unlike the
# other tests of this directory it is NOT self-contained : it drives a REAL Proxmox
# through the devkits, so it needs a reachable node and a working vault.
#
# It cleans up after itself, including on failure, through a trap. Pass --keep to leave
# the network standing for inspection.
#
# The VM attach step is skipped unless a VM id is given. That step is destructive on the
# VM's network card : it is deleted and recreated, so its MAC changes. Never point it at
# a VM you reach through the card being moved.
#
# USAGE
#   ./07.sdn_network_chain_tests.sh [--keep] [node] [zone] [vnet] [cidr] [gateway] [vm_id]
#   ./07.sdn_network_chain_tests.sh
#   ./07.sdn_network_chain_tests.sh --keep px-testing r42test net199 192.168.199.0/24 192.168.199.1 102
#

set -uo pipefail
IFS=$'\n\t'

KEEP=false
[ "${1:-}" = "--keep" ] && { KEEP=true ; shift ; }

NODE="${1:-px-testing}"
ZONE="${2:-r42test}"
VNET="${3:-net199}"
CIDR="${4:-192.168.199.0/24}"
GW="${5:-192.168.199.1}"
VMID="${6:-}"

SUBNET_ID="${ZONE}-${CIDR//\//-}"

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

assert_nonempty() {
  local label="$1" actual="$2"
  if [ -n "$actual" ]; then
    echo "  PASS  $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL  $label (empty)"
    FAIL=$((FAIL+1))
  fi
}

assert_exit_zero() {
  local label="$1" ; shift
  if "$@" >/dev/null 2>&1 ; then
    echo "  PASS  $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL  $label (expected exit 0, got $?)"
    FAIL=$((FAIL+1))
  fi
}

section() { echo ; echo "== $1" ; }

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# Helpers
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

## Counting the live SNAT rules WITHOUT deleting any : asking to reconcile down to a
## count higher than the real one makes the action a pure counter. It reports
## snat_before, and deletes nothing because nothing is in excess.
count_snat() {
  printf '{"proxmox_node":"%s","sdn_subnet_cidr":"%s","sdn_snat_want":99}\n' "$NODE" "$CIDR" \
    | proxmox_network.sdn_subnet_cidr.delete_extra_snat_rules.to.jsons.sh --json 2>/dev/null \
    | jq -r '.snat_before // "?"' | head -1
}

net_line() { printf '{"proxmox_node":"%s","sdn_zone":"%s","sdn_vnet":"%s","sdn_subnet":"%s"}\n' \
             "$NODE" "$ZONE" "$VNET" "$CIDR" ; }

## Alimentees explicitement, et pas seulement parce que ce script est lance depuis un
## terminal. Le normaliseur de chaque devkit fait : si stdin est un tty, prendre le noeud
## du vault, SINON lire stdin. Depuis un terminal cela marche par accident ; lance avec
## son stdin redirige, depuis cron ou dans un pipe, il lirait le vide et ces fonctions
## renverraient toutes une chaine vide, faisant echouer chaque assertion pour une raison
## qui n'a rien a voir avec ce qu'elles testent.
node_line() { printf '{"proxmox_node":"%s"}\n' "$NODE" ; }

zone_in_list()   { node_line | proxmox_network.datacenter.list_sdn_zones.to.jsons.sh --json 2>/dev/null \
                   | jq -r --arg z "$ZONE" 'select(.zone==$z) | .zone' | head -1 ; }
vnet_in_list()   { node_line | proxmox_network.datacenter.list_sdn_vnets.to.jsons.sh --json 2>/dev/null \
                   | jq -r --arg v "$VNET" 'select(.vnet==$v) | .vnet' | head -1 ; }
subnet_in_list() { node_line | proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh --json 2>/dev/null \
                   | jq -r --arg s "$SUBNET_ID" 'select(.subnet==$s) | .subnet' | head -1 ; }
subnet_snat()    { node_line | proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh --json 2>/dev/null \
                   | jq -r --arg s "$SUBNET_ID" 'select(.subnet==$s) | .subnet_snat' | head -1 ; }

cleanup() {
  local rc=$?
  if $KEEP ; then
    echo ; echo "-- --keep : the network is left standing"
    echo "   take it down with :"
    echo "     $(net_line) | proxmox_network.datacenter.delete_sdn_network.to.jsons.sh"
  else
    echo ; echo "-- cleanup"
    net_line | proxmox_network.datacenter.delete_sdn_network.to.jsons.sh >/dev/null 2>&1 \
      && echo "   network removed" || echo "   cleanup itself failed, check by hand"
  fi
  echo
  echo "=================================================="
  printf " PASS %s   FAIL %s\n" "$PASS" "$FAIL"
  echo "=================================================="
  [ "$FAIL" -eq 0 ] || exit 1
  exit "$rc"
}
trap cleanup EXIT

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

echo "sdn network chain tests"
echo "  node=$NODE zone=$ZONE vnet=$VNET cidr=$CIDR gw=$GW"
echo "  derived subnet id : $SUBNET_ID"
echo "  vm attach step    : ${VMID:-skipped, no vm_id given}"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
section "1. a teardown from an unknown state must succeed"
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
## The chain of section 9 starts with a teardown, so the test can only be replayable if
## deleting what is absent is a no-op rather than a failure. This is the check that makes
## every following run possible.

OUT=$(net_line | proxmox_network.datacenter.delete_sdn_network.to.jsons.sh 2>/dev/null | tail -1)
assert_nonempty "delete on unknown state returns a summary" "$OUT"
assert_eq "nothing is left in the zone list" "" "$(zone_in_list)"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
section "2. create builds the three objects and applies them"
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUT=$(printf '{"proxmox_node":"%s","sdn_zone":"%s","sdn_vnet":"%s","sdn_subnet":"%s","sdn_subnet_gateway":"%s","sdn_subnet_snat":1}\n' \
      "$NODE" "$ZONE" "$VNET" "$CIDR" "$GW" \
      | proxmox_network.datacenter.create_sdn_network.to.jsons.sh 2>/dev/null | tail -1)
assert_nonempty "create returns a summary"      "$OUT"
assert_eq "the zone is listed"    "$ZONE"      "$(zone_in_list)"
assert_eq "the vnet is listed"    "$VNET"      "$(vnet_in_list)"
assert_eq "the subnet is listed"  "$SUBNET_ID" "$(subnet_in_list)"
assert_eq "the derived id matches what Proxmox built" "$SUBNET_ID" \
          "$(printf '%s' "$OUT" | jq -r '.subnet')"
assert_eq "snat is declared on"   "1"          "$(subnet_snat)"
assert_eq "exactly one live SNAT rule after create" "1" "$(count_snat)"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
section "3. create again is a clean no-op"
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
## Not idempotence in the ansible sense : the writes are skipped by lookup, the apply
## and the reconciliation still run. What matters is that it does not fail and does not
## duplicate, and that the rule count comes back to one rather than climbing.

OUT=$(printf '{"proxmox_node":"%s","sdn_zone":"%s","sdn_vnet":"%s","sdn_subnet":"%s","sdn_subnet_gateway":"%s","sdn_subnet_snat":1}\n' \
      "$NODE" "$ZONE" "$VNET" "$CIDR" "$GW" \
      | proxmox_network.datacenter.create_sdn_network.to.jsons.sh 2>/dev/null | tail -1)
assert_eq "the three writes are skipped" "3" "$(printf '%s' "$OUT" | jq -r '.steps_skipped')"
assert_eq "still exactly one live SNAT rule" "1" "$(count_snat)"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
section "4. the outgoing NAT switch, off then on then toggled"
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
## This is the path that orphans a rule if the reconciliation is skipped : snat=0 removes
## the post-down hook before it ever runs. So the count is what proves the cut, not the
## declaration.

proxmox_network.sdn_subnet_id.disable_outgoing_nat.to.jsons.sh "$SUBNET_ID" >/dev/null 2>&1
assert_eq "declaration says snat off"        "0" "$(subnet_snat)"
assert_eq "no live SNAT rule left"           "0" "$(count_snat)"

proxmox_network.sdn_subnet_id.enable_outgoing_nat.to.jsons.sh "$SUBNET_ID" >/dev/null 2>&1
assert_eq "declaration says snat on"         "1" "$(subnet_snat)"
assert_eq "one live SNAT rule again"         "1" "$(count_snat)"

proxmox_network.sdn_subnet_id.toggle_outgoing_nat.to.jsons.sh "$SUBNET_ID" >/dev/null 2>&1
assert_eq "toggle flipped it off"            "0" "$(subnet_snat)"
assert_eq "and the live rule followed"       "0" "$(count_snat)"

proxmox_network.sdn_subnet_id.toggle_outgoing_nat.to.jsons.sh "$SUBNET_ID" >/dev/null 2>&1
assert_eq "toggle flipped it back on"        "1" "$(subnet_snat)"
assert_eq "and the live rule followed again" "1" "$(count_snat)"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
section "5. attach a VM to the vnet"
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [ -z "$VMID" ]; then
  echo "  SKIP  no vm_id given, pass it as the 6th argument"
else
  CARD=$(printf '{"proxmox_node":"%s","vm_id":%s}\n' "$NODE" "$VMID" \
         | proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh --json 2>/dev/null | head -1)
  assert_nonempty "the VM has at least one card" "$CARD"

  ## The id is what a delete addresses. Its absence from the list output is the bug this
  ## chantier fixed, so asserting it here is what stops it coming back.
  NETID=$(printf '%s' "$CARD" | jq -r '.vm_vmnet_id // empty')
  assert_nonempty "the list output carries vm_vmnet_id" "$NETID"

  if [ -n "$NETID" ]; then
    printf '{"proxmox_node":"%s","vm_id":%s,"vm_vmnet_id":%s,"iface_bridge":"%s"}\n' \
      "$NODE" "$VMID" "$NETID" "$VNET" \
      | proxmox_network.vm_id.replace_interfaces_vm.to.jsons.sh >/dev/null 2>&1
    ATTACHED=$(printf '{"proxmox_node":"%s","vm_id":%s}\n' "$NODE" "$VMID" \
               | proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh --json 2>/dev/null \
               | jq -r --arg b "$VNET" 'select(.vm_network_bridge==$b) | .vm_network_bridge' | head -1)
    assert_eq "the VM card now sits on the vnet" "$VNET" "$ATTACHED"

    ## Replaying it must be a no-op, not a second card.
    OUT=$(printf '{"proxmox_node":"%s","vm_id":%s,"vm_vmnet_id":%s,"iface_bridge":"%s"}\n' \
          "$NODE" "$VMID" "$NETID" "$VNET" \
          | proxmox_network.vm_id.replace_interfaces_vm.to.jsons.sh 2>/dev/null | tail -1)
    assert_eq "replaying the move is skipped" "skipped" "$(printf '%s' "$OUT" | jq -r '.verdict')"
  fi
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
section "6. teardown leaves nothing, and replays cleanly"
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
## A vnet still carrying a VM card cannot be removed by Proxmox, so if a VM was attached
## the teardown is expected to be refused here. That is correct behaviour, not a defect,
## and the message says which one it is.

if [ -n "$VMID" ]; then
  echo "  NOTE  a VM is attached to $VNET, the teardown below may be refused by Proxmox"
  echo "        detach it first : echo '{...\"iface_bridge\":\"vmbr0\"...}' | replace_interfaces_vm"
fi

OUT=$(net_line | proxmox_network.datacenter.delete_sdn_network.to.jsons.sh 2>/dev/null | tail -1)
assert_nonempty "teardown returns a summary" "$OUT"

if [ -z "$VMID" ]; then
  assert_eq "the zone is gone"   "" "$(zone_in_list)"
  assert_eq "the vnet is gone"   "" "$(vnet_in_list)"
  assert_eq "the subnet is gone" "" "$(subnet_in_list)"
  assert_eq "no live SNAT rule survives its declaration" "0" "$(count_snat)"

  OUT=$(net_line | proxmox_network.datacenter.delete_sdn_network.to.jsons.sh 2>/dev/null | tail -1)
  assert_eq "a second teardown skips all three writes" "3" \
            "$(printf '%s' "$OUT" | jq -r '.steps_skipped')"
fi
