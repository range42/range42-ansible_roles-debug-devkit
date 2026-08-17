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
# THE VM STEP, AND WHY IT ASKS BEFORE MOVING ANYTHING
# It is skipped unless a VM id is given. It is the only destructive step of this file : the
# card is deleted and recreated by the role, so ITS MAC CHANGES, twice over a round trip.
# Never point it at a VM you reach through the card being moved.
#
# Because it is destructive it is gated : the VM is looked up on the node first, and each
# leg of the move is confirmed on the terminal before it runs. Refusing a leg skips it,
# it does not fail the run. Without a terminal the gate refuses rather than assumes yes,
# so this file is safe to launch from anything non interactive - it will just report the
# VM step as skipped. Pass --yes to answer for it.
#
# THE ROUND TRIP
# By default the card goes to the vnet AND comes back to the bridge it was found on, which
# is what makes the whole chain testable : a vnet still carrying a card cannot be deleted,
# so only a returned card lets section 6 assert a complete teardown. The return leg also
# runs from the trap, so an interrupt between the two legs cannot strand the card on a
# vnet that is about to be removed.
#
# Pass --vm-stay to keep the card on the vnet for inspection. The teardown will then be
# refused by Proxmox, on purpose, and the command to detach by hand is printed.
#
# USAGE
#   ./07.sdn_network_chain_tests.sh [flags] [node] [zone] [vnet] [cidr] [gateway] [vm_id] [return_bridge]
#
#   flags : --keep            leave the SDN network standing at the end
#           --vm-round-trip   move the card to the vnet and back (the default)
#           --vm-stay         move the card to the vnet and leave it there
#           --yes | -y        do not ask before moving a card
#
#   ./07.sdn_network_chain_tests.sh
#   ./07.sdn_network_chain_tests.sh px-testing r42test net199 192.168.199.0/24 192.168.199.1 102
#   ./07.sdn_network_chain_tests.sh --vm-stay px-testing r42test net199 192.168.199.0/24 192.168.199.1 102
#   ./07.sdn_network_chain_tests.sh --yes px-testing r42test net199 192.168.199.0/24 192.168.199.1 102 vmbr0
#
# return_bridge is optional : the card goes back to the bridge it was found on. Give it
# only when that is not what you want, or when the card already sits on the vnet and
# there is therefore nothing to deduce.
#

set -uo pipefail
IFS=$'\n\t'

KEEP=false
ROUND_TRIP=true
ASSUME_YES=false

while [ $# -gt 0 ]; do
  case "$1" in
    --keep)          KEEP=true ;;
    --vm-round-trip) ROUND_TRIP=true ;;
    --vm-stay)       ROUND_TRIP=false ;;
    --yes|-y)        ASSUME_YES=true ;;
    -h|--help)       sed -n '3,50p' "$0" ; exit 0 ;;
    --*|-?)          echo "unknown flag : $1" >&2 ; exit 2 ;;
    *)               break ;;
  esac
  shift
done

NODE="${1:-px-testing}"
ZONE="${2:-r42test}"
VNET="${3:-net199}"
CIDR="${4:-192.168.199.0/24}"
GW="${5:-192.168.199.1}"
VMID="${6:-}"
RETURN_BRIDGE="${7:-}"

SUBNET_ID="${ZONE}-${CIDR//\//-}"

## State of the card, kept out here because the trap reads it. CARD_ON_VNET is the fact
## the trap acts on : it is true only between the two legs of the move.
CARD_ON_VNET=false
MOVED_NETID=""

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

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# The VM side : lookup, gate, move
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

## Does the VM exist, and in what shape. Answers "<name> (<status>)" or nothing at all.
## This devkit reads a bare vm_id on stdin and resolves the node from the vault, so it
## answers for the vault's node ; the authoritative check against $NODE is the card read
## below, which does take proxmox_node. Here it only feeds the confirmation banner with
## something a human can recognise before agreeing to destroy a card.
vm_probe() {
  printf '%s\n' "$VMID" \
    | proxmox_vm.vm_id.list_vm_and_extract_vm_name_with_api.to.jsons.sh --json 2>/dev/null \
    | jq -r 'select(.vm_id != null) | "\(.vm_name) (\(.vm_status))"' | head -1
}

## Which bridge net<$1> sits on right now. Read back from Proxmox rather than remembered,
## because the point of the assertions is to check what the API says, not what we think we
## asked for.
card_bridge() {
  printf '{"proxmox_node":"%s","vm_id":%s}\n' "$NODE" "$VMID" \
    | proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh --json 2>/dev/null \
    | jq -r --argjson n "$1" 'select(.vm_vmnet_id == $n) | .vm_network_bridge' | head -1
}

## Which card of the VM, if any, already sits on the vnet. Read before anything else runs,
## because a card left there by an earlier --vm-stay changes what section 1 can do.
vm_card_on_vnet() {
  printf '{"proxmox_node":"%s","vm_id":%s}\n' "$NODE" "$VMID" \
    | proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh --json 2>/dev/null \
    | jq -r --arg b "$VNET" 'select(.vm_network_bridge==$b) | .vm_vmnet_id' | head -1
}

## One summary line : move net<$1> onto bridge $2. stderr is kept, a failed move must be
## visible ; the summary is the last line because the composite also relays the delete and
## the add it performs.
move_card() {
  printf '{"proxmox_node":"%s","vm_id":%s,"vm_vmnet_id":%s,"iface_bridge":"%s"}\n' \
    "$NODE" "$VMID" "$1" "$2" \
    | proxmox_network.vm_id.replace_interfaces_vm.to.jsons.sh 2>/dev/null | tail -1
}

## The command a human runs to do the same by hand. Printed whenever the script leaves a
## card somewhere it should not stay, so the way out is on screen and not in a doc.
move_card_cmd() {
  echo "     echo '{\"proxmox_node\":\"$NODE\",\"vm_id\":$VMID,\"vm_vmnet_id\":$1,\"iface_bridge\":\"$2\"}' \\"
  echo "       | proxmox_network.vm_id.replace_interfaces_vm.to.jsons.sh | jq -c"
}

## The single gate every card move goes through. Two refusals are not the same thing :
## answering no is a choice and is reported as such, having no terminal is an absence of
## anybody to ask and must never be read as consent.
confirm() {
  ## ans is initialised : a Ctrl-D on the prompt leaves read without assigning, and an
  ## unset variable under set -u would abort the run instead of declining the step.
  local what="$1" ans=""
  echo "  -->  $what"
  if $ASSUME_YES ; then
    echo "       --yes given, not asking"
    return 0
  fi
  if [ ! -t 0 ]; then
    echo "       no terminal to ask on, and --yes was not given : refused"
    return 1
  fi
  printf '       type yes to proceed, anything else to skip : '
  read -r ans
  case "$ans" in
    yes|YES|y|Y) return 0 ;;
    *)           echo "       skipped on your answer" ; return 1 ;;
  esac
}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

cleanup() {
  local rc=$?

  ## The card comes back BEFORE the network goes down, and the order is not cosmetic :
  ## Proxmox refuses to delete a vnet that still carries one. Running this from the trap
  ## rather than only at the end of section 5 is what covers an interrupt, a failed
  ## assertion or a refused second leg - anything that leaves the card mid-journey.
  if $CARD_ON_VNET && $ROUND_TRIP ; then
    echo ; echo "-- the card is still on $VNET, putting it back on $RETURN_BRIDGE"
    RES=$(move_card "$MOVED_NETID" "$RETURN_BRIDGE")
    if [ "$(printf '%s' "$RES" | jq -r '.verdict // empty' 2>/dev/null)" = "ok" ]; then
      echo "   restored on $(card_bridge "$MOVED_NETID")"
      CARD_ON_VNET=false
    else
      echo "   THE RESTORE FAILED, the teardown below will be refused. By hand :"
      move_card_cmd "$MOVED_NETID" "$RETURN_BRIDGE"
    fi
  fi

  if $CARD_ON_VNET ; then
    echo ; echo "-- vm $VMID keeps net$MOVED_NETID on $VNET"
    echo "   so the vnet cannot be deleted until it is detached :"
    move_card_cmd "$MOVED_NETID" "${RETURN_BRIDGE:-vmbr0}"
  fi

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
if [ -z "$VMID" ]; then
  echo "  vm step           : skipped, no vm_id given"
else
  $ROUND_TRIP && MODE="round trip, the card comes back" || MODE="--vm-stay, the card stays on $VNET"
  echo "  vm step           : vm $VMID, $MODE"
  $ASSUME_YES && echo "  confirmation      : --yes, not asking" \
              || echo "  confirmation      : asked before each leg"

  ## Said here rather than discovered as a mystery failure two sections later. A card left
  ## on the vnet by an earlier run makes Proxmox refuse the teardown of section 1, so one
  ## assertion there WILL fail. Section 5 detaches it, which is what lets section 6 pass.
  STRANDED=$(vm_card_on_vnet)
  if [ -n "$STRANDED" ]; then
    echo
    echo "  NOTE  net$STRANDED of vm $VMID already sits on $VNET, left by an earlier run"
    echo "        section 1 cannot delete a vnet that carries a card : expect 1 failure"
    echo "        there. Section 5 brings the card back, section 6 then passes in full."
    [ -n "$RETURN_BRIDGE" ] || echo "        give the return bridge as the 7th argument, or nothing will be moved"
  fi
fi

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
section "5. move a VM card onto the vnet, and back"
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
## The only destructive section. Nothing here runs without a lookup that proves the VM is
## there and a confirmation on the terminal, and every step reads its result back from the
## API rather than trusting the call it just made.

if [ -z "$VMID" ]; then
  echo "  SKIP  no vm_id given, pass it as the 6th argument"
else
  VM_DESC=$(vm_probe)
  if [ -n "$VM_DESC" ]; then
    echo "  the node knows vm $VMID : $VM_DESC"
  else
    echo "  NOTE  vm $VMID was not found by the cluster lookup"
    echo "        that lookup answers for the vault's node ; the card read below decides"
  fi

  CARD=$(printf '{"proxmox_node":"%s","vm_id":%s}\n' "$NODE" "$VMID" \
         | proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh --json 2>/dev/null | head -1)
  assert_nonempty "the VM exists on $NODE and has at least one card" "$CARD"

  ## The id is what a delete addresses. Its absence from the list output is the bug this
  ## chantier fixed, so asserting it here is what stops it coming back.
  NETID=$(printf '%s' "$CARD" | jq -r '.vm_vmnet_id // empty')
  assert_nonempty "the list output carries vm_vmnet_id" "$NETID"

  ORIG_BRIDGE=$(printf '%s' "$CARD" | jq -r '.vm_network_bridge // empty')

  ## Where the card goes home to. Deduced from where it was found, unless the caller said
  ## otherwise. A card already sitting on the vnet leaves nothing to deduce : moving it
  ## there would be a no-op and bringing it "back" would mean back to the vnet, so rather
  ## than invent a bridge the section stops and says which argument is missing.
  [ -n "$RETURN_BRIDGE" ] || RETURN_BRIDGE="$ORIG_BRIDGE"

  if [ -z "$NETID" ] || [ -z "$ORIG_BRIDGE" ]; then
    echo "  SKIP  the card could not be read, nothing will be moved"
  elif [ "$RETURN_BRIDGE" = "$VNET" ]; then
    echo "  SKIP  net$NETID is already on $VNET and no return bridge was given"
    echo "        pass it as the 7th argument, for instance vmbr0"
  else
    ## The return leg is a function because it has two callers : the normal path, and the
    ## resume path of a card found already on the vnet - a run left that way by --vm-stay,
    ## or interrupted. Duplicating it would be duplicating the confirmation gate.
    leg_return() {
      local netid="$1" out back
      if ! $ROUND_TRIP ; then
        echo "  --vm-stay : the card is left on $VNET"
        return 0
      fi
      confirm "delete and recreate net$netid of vm $VMID, $VNET -> $RETURN_BRIDGE (the MAC changes again)" \
        || return 0
      out=$(move_card "$netid" "$RETURN_BRIDGE")
      assert_eq "the return leg reports it came off the vnet" "$VNET" \
                "$(printf '%s' "$out" | jq -r '.iface_bridge_from // empty')"
      back=$(card_bridge "$netid")
      assert_eq "the card is back on $RETURN_BRIDGE" "$RETURN_BRIDGE" "$back"
      ## The trap is released on the API's word and not on the call having been made : if
      ## the card did not actually come back, the trap must still try.
      [ "$back" = "$RETURN_BRIDGE" ] && CARD_ON_VNET=false
      return 0
    }

    if [ "$ORIG_BRIDGE" = "$VNET" ]; then
      #### resume : the outbound leg was already played by an earlier run
      echo "  net$NETID is already on $VNET, only the return to $RETURN_BRIDGE is left"
      MOVED_NETID="$NETID"
      CARD_ON_VNET=true
      leg_return "$NETID"
    else
      echo "  net$NETID is on $ORIG_BRIDGE, it will go to $VNET and back to $RETURN_BRIDGE"

      #### leg 1 : onto the vnet
      if confirm "delete and recreate net$NETID of vm $VMID, $ORIG_BRIDGE -> $VNET (the MAC changes)" ; then
        OUT=$(move_card "$NETID" "$VNET")
        ## Recorded before the assertions : if one of them exits the script, the trap still
        ## has to know the card is out there.
        MOVED_NETID="$NETID"
        CARD_ON_VNET=true

        assert_eq "the move reports where the card came from" "$ORIG_BRIDGE" \
                  "$(printf '%s' "$OUT" | jq -r '.iface_bridge_from // empty')"
        assert_eq "the VM card now sits on the vnet" "$VNET" "$(card_bridge "$NETID")"

        ## Replaying it must be a no-op, not a second card.
        OUT=$(move_card "$NETID" "$VNET")
        assert_eq "replaying the move is skipped" "skipped" \
                  "$(printf '%s' "$OUT" | jq -r '.verdict // empty')"

        #### leg 2 : back home
        leg_return "$NETID"
      fi
    fi
  fi
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
section "6. teardown leaves nothing, and replays cleanly"
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
## A vnet still carrying a VM card cannot be removed by Proxmox, so the full teardown is
## only asserted when nothing of ours is left attached : no VM was given, the card came
## back, or the move never happened. Under --vm-stay the refusal is the expected outcome,
## not a defect, and the way out is printed rather than asserted.

if $CARD_ON_VNET ; then
  echo "  NOTE  net$MOVED_NETID is still on $VNET, so Proxmox will refuse the teardown"
  echo "        that is the expected outcome here, detach with :"
  move_card_cmd "$MOVED_NETID" "$RETURN_BRIDGE"
fi

OUT=$(net_line | proxmox_network.datacenter.delete_sdn_network.to.jsons.sh 2>/dev/null | tail -1)
assert_nonempty "teardown returns a summary" "$OUT"

if ! $CARD_ON_VNET ; then
  assert_eq "the zone is gone"   "" "$(zone_in_list)"
  assert_eq "the vnet is gone"   "" "$(vnet_in_list)"
  assert_eq "the subnet is gone" "" "$(subnet_in_list)"
  assert_eq "no live SNAT rule survives its declaration" "0" "$(count_snat)"

  OUT=$(net_line | proxmox_network.datacenter.delete_sdn_network.to.jsons.sh 2>/dev/null | tail -1)
  assert_eq "a second teardown skips all three writes" "3" \
            "$(printf '%s' "$OUT" | jq -r '.steps_skipped')"
fi
