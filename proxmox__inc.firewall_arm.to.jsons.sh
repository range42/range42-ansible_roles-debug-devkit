#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# SHARED LOGIC for the four arming composites :
#
#     proxmox_firewall.vm_ids.arm            guests-arm      ids on stdin
#     proxmox_firewall.vm_ids.disarm         guests-disarm   ids on stdin
#     proxmox_firewall.proxmox_node.arm      host-arm
#     proxmox_firewall.proxmox_node.disarm   host-disarm
#
# Arming a guest is NOT one call, it is a sequence, and the order is the whole safety of it :
# the way back in must exist before anything filters. The bundles firewall.enable.vm(s) and
# firewall.disable.vm(s) proved that order ; this file runs the same steps through the
# unitary devkits, which take the api fast path, so a guest costs seconds instead of a play.
#
#     GUEST, arm     : ssh accept posted (or already there), then every card flagged, then the
#                      guest switch on ; read back ; refuse to report a guest that is not set up
#                      to filter
#     GUEST, disarm  : the guest switch off, then every card unflagged, then the ssh accept
#                      re-posted so a later arming stays safe ; read back
#     HOST, arm      : management access guaranteed at the datacenter then at the node (8006 and
#                      22 accepted above any deny), then the datacenter switch on, then the node
#                      switch ; both guards refuse to arm a level whose management ports are not
#                      accepted ; read back
#     HOST, disarm   : the datacenter switch off, then the node switch ; the management accepts
#                      are kept ; read back
#
# The reads (cards, switches, flags) come from the show_firewall engine in ONE call per read,
# so a sweep of N guests costs 2 reads, not 2N. A guest the node does not run is skipped and
# said (declared, not deployed) ; a guest with no card refuses the whole run before anything is
# written, as the single guest bundle does ; the first refused step ends the run and names the
# guest, the guests before it are done.
#
# OUTPUT : the lines of every unitary pass through, then ONE summary line per guest
# (firewall_arm_guest / firewall_disarm_guest) or per host (firewall_arm_host /
# firewall_disarm_host), so a caller renders the verdicts from the summary lines alone.
#
# USAGE :  <this> guests-arm|guests-disarm|host-arm|host-disarm
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

MODE="${1:-}"

_trace() { devkit_utils.text.echo_trace.to.text.to.stderr.sh "$@" ; }
_error() { devkit_utils.text.echo_error.to.text.to.stderr.sh "$@" ; }

case "$MODE" in
  guests-arm|guests-disarm|host-arm|host-disarm) ;;
  *) _error "usage : $(basename "$0") guests-arm|guests-disarm|host-arm|host-disarm" ; exit 1 ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# one unitary call : its json lines pass through to stdout, and are kept for the verdict.
# A failure ends the run here, the unitary has already said why on stderr.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

STEP_OUT=""
_step() {
  local label="$1" input="$2" ; shift 2
  if ! STEP_OUT="$(printf '%s\n' "$input" | "$@" --json)" ; then
    _error "${label} stopped the run - see the refusal above, then read the state with proxmox_firewall.scenario.show_firewall.to.jsons.sh --table"
    exit 1
  fi
  [[ -z "$STEP_OUT" ]] || printf '%s\n' "$STEP_OUT"
}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# THE HOST
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ "$MODE" == host-arm || "$MODE" == host-disarm ]]; then
  BEFORE="$(proxmox_firewall.datacenter.show_firewall.to.jsons.sh --json | jq -cs '[ .[] | select(.level == "host") ] | first // empty')"
  [[ -n "$BEFORE" ]] || { _error "cannot read the host switches (the show_firewall engine returned no host line) : nothing was changed" ; exit 1 ; }
  NODE="$(printf '%s' "$BEFORE" | jq -r '.proxmox_node')"
  DC_BEFORE="$(printf '%s' "$BEFORE" | jq -r '(.datacenter_enable // 0) | tostring')"
  NODE_BEFORE="$(printf '%s' "$BEFORE" | jq -r '(.node_enable // 0) | tostring')"

  if [[ "$MODE" == host-arm ]]; then
    _trace "host : management access first, at the datacenter then at the node, then the two switches"
    _step "the management access of the datacenter" "$NODE" proxmox_firewall.datacenter.enable_management_access.to.jsons.sh
    _step "the management access of the node"       "$NODE" proxmox_firewall.proxmox_node.enable_management_access.to.jsons.sh
    _step "the datacenter switch"                   "$NODE" proxmox_firewall.datacenter.enable_firewall.to.jsons.sh
    _step "the node switch"                         "$NODE" proxmox_firewall.proxmox_node.enable_firewall.to.jsons.sh
    WANT=1 ; ACTION="firewall_arm_host" ; ACCESS="management access guaranteed on 8006 and 22"
  else
    _trace "host : the datacenter switch off first, then the node switch ; the management accepts are kept"
    _step "the datacenter switch" "$NODE" proxmox_firewall.datacenter.disable_firewall.to.jsons.sh
    _step "the node switch"       "$NODE" proxmox_firewall.proxmox_node.disable_firewall.to.jsons.sh
    WANT=0 ; ACTION="firewall_disarm_host" ; ACCESS="management accepts kept in place"
  fi

  AFTER="$(proxmox_firewall.datacenter.show_firewall.to.jsons.sh --json | jq -cs '[ .[] | select(.level == "host") ] | first // empty')"
  [[ -n "$AFTER" ]] || { _error "cannot read the host switches back" ; exit 1 ; }
  DC_AFTER="$(printf '%s' "$AFTER" | jq -r '(.datacenter_enable // 0) | tostring')"
  NODE_AFTER="$(printf '%s' "$AFTER" | jq -r '(.node_enable // 0) | tostring')"

  jq -nc \
    --arg action "$ACTION" --arg node "$NODE" --arg access "$ACCESS" \
    --argjson dcb "$DC_BEFORE" --argjson dca "$DC_AFTER" --argjson nb "$NODE_BEFORE" --argjson na "$NODE_AFTER" --argjson want "$WANT" \
    '{
      action: $action,
      source: "proxmox",
      proxmox_node: $node,
      datacenter_before: $dcb,
      datacenter_after: $dca,
      node_before: $nb,
      node_after: $na,
      management_access: $access,
      as_asked: (($dca == $want) and ($na == $want))
    }'
  if [[ "$DC_AFTER" != "$WANT" || "$NODE_AFTER" != "$WANT" ]]; then
    _error "a host switch did not follow : datacenter ${DC_BEFORE} -> ${DC_AFTER}, node ${NODE_BEFORE} -> ${NODE_AFTER}, wanted ${WANT} on both"
    exit 1
  fi
  exit 0
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# THE GUESTS : ids on stdin, plain or json lines
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [ -t 0 ]; then
  _error "no input on stdin : pipe the vm_id(s), one per line (plain text or json lines)"
  exit 1
fi
IDS="$(jq -R -r '(fromjson? // .) as $v | if ($v | type) == "object" then ($v.vm_id // empty | tostring) else ($v | tostring) end' | grep -E '^[0-9]+$' | awk '!seen[$0]++' || true)"
[[ -n "$IDS" ]] || { _error "no vm_id read on stdin, nothing to do" ; exit 1 ; }
N_IDS="$(printf '%s\n' "$IDS" | grep -c .)"

# one read for every guest : the cards, the switches, the flags, and whether the node runs it
STATE="$(printf '%s\n' "$IDS" | proxmox_firewall.show_firewall.to.jsons.sh --scope vm_ids --json || true)"
[[ -n "$STATE" ]] || { _error "cannot read the guests (the show_firewall engine returned nothing) : nothing was changed" ; exit 1 ; }
NODE="$(printf '%s\n' "$STATE" | jq -rs '[ .[] | select(.level == "host") | .proxmox_node ] | first // empty')"

# the plan : per guest, its level and its cards ; refusals BEFORE anything is written
PLAN="$(printf '%s\n' "$STATE" | jq -c --argjson ids "$(printf '%s\n' "$IDS" | jq -R 'tonumber' | jq -sc .)" '
  [ inputs ] as $all
  | $ids[] as $id
  | ($all | map(select(.vm_id == $id))) as $mine
  | {
      vm_id: $id,
      vm_name: (($mine | map(.vm_name // empty) | first) // ""),
      level: (if ($mine | any(.level == "card")) then "card" elif ($mine | any(.level == "absent")) then "absent" elif ($mine | any(.level == "error")) then "error" elif ($mine | any(.level == "guest")) then "guest" else "unread" end),
      cards: [ $mine[] | select(.level == "card") | .vm_network_device ],
      guest_enable: (($mine | map(.guest_enable) | first) // null)
    }' --null-input 2>/dev/null || true)"
[[ -n "$PLAN" ]] || { _error "cannot build the plan from the engine's lines : nothing was changed" ; exit 1 ; }

UNREAD="$(printf '%s\n' "$PLAN" | jq -r 'select(.level == "error" or .level == "unread") | .vm_id' | paste -sd ' ' -)"
[[ -z "$UNREAD" ]] || { _error "guest(s) that could not be read : ${UNREAD}. Nothing was changed. Read them with proxmox_firewall.vm_ids.show_firewall.to.jsons.sh --table" ; exit 1 ; }
NOCARD="$(printf '%s\n' "$PLAN" | jq -r 'select(.level == "guest") | .vm_id' | paste -sd ' ' -)"
[[ -z "$NOCARD" ]] || { _error "guest(s) with no card to flag : ${NOCARD}. NOTHING was changed : a guest filters through its card flag, and this one has none" ; exit 1 ; }
ABSENT="$(printf '%s\n' "$PLAN" | jq -r 'select(.level == "absent") | .vm_id' | paste -sd ' ' -)"
[[ -z "$ABSENT" ]] || _trace "declared, not deployed on this node, skipped : ${ABSENT}"
TODO="$(printf '%s\n' "$PLAN" | jq -c 'select(.level == "card")')"
[[ -n "$TODO" ]] || { _error "none of the ${N_IDS} guest(s) is deployed on this node : nothing to do" ; exit 1 ; }

if [[ "$MODE" == guests-arm ]]; then ACTION="firewall_arm_guest" ; VERB="arming" ; else ACTION="firewall_disarm_guest" ; VERB="disarming" ; fi
_trace "${VERB} $(printf '%s\n' "$TODO" | grep -c .) guest(s) on ${NODE}, in order : $(printf '%s\n' "$TODO" | jq -r '.vm_id' | paste -sd ' ' -)"

declare -A SSH_STATE
while IFS= read -r G ; do
  [[ -z "$G" ]] && continue
  ID="$(printf '%s' "$G" | jq -r '.vm_id')"
  NAME="$(printf '%s' "$G" | jq -r '.vm_name')"
  CARDS="$(printf '%s' "$G" | jq -r '.cards[]')"
  if [[ "$MODE" == guests-arm ]]; then
    _step "guest ${ID} (${NAME}), the ssh accept" "$ID" proxmox_firewall.vm_id.enable_default_ssh_rules.to.jsons.sh
    SSH_STATE[$ID]="$(printf '%s\n' "$STEP_OUT" | jq -rs '[ .[] | select(.vm_fw_rule == "ssh_accept") | if (.vm_fw_already_present | tostring | ascii_downcase) == "true" then "already" else "posted" end ] | first // "unknown"')"
    while IFS= read -r C ; do
      [[ -z "$C" ]] && continue
      _step "guest ${ID} (${NAME}), the card ${C}" "$(jq -nc --argjson id "$ID" --argjson n "${C#net}" '{vm_id: $id, vm_vmnet_id: $n}')" proxmox_firewall.vm_id.enable_firewall_iface.to.jsons.sh
    done <<< "$CARDS"
    _step "guest ${ID} (${NAME}), the switch" "$ID" proxmox_firewall.vm_id.enable_firewall.to.jsons.sh
  else
    _step "guest ${ID} (${NAME}), the switch" "$ID" proxmox_firewall.vm_id.disable_firewall.to.jsons.sh
    while IFS= read -r C ; do
      [[ -z "$C" ]] && continue
      _step "guest ${ID} (${NAME}), the card ${C}" "$(jq -nc --argjson id "$ID" --argjson n "${C#net}" '{vm_id: $id, vm_vmnet_id: $n}')" proxmox_firewall.vm_id.disable_firewall_iface.to.jsons.sh
    done <<< "$CARDS"
    # the way back in stays : a later arming must find its accept
    _step "guest ${ID} (${NAME}), the ssh accept kept" "$ID" proxmox_firewall.vm_id.enable_default_ssh_rules.to.jsons.sh
    SSH_STATE[$ID]="kept"
  fi
done <<< "$TODO"

# read back, once for every guest, and refuse to report what is not true
AFTER="$(printf '%s\n' "$TODO" | jq -r '.vm_id' | proxmox_firewall.show_firewall.to.jsons.sh --scope vm_ids --json || true)"
[[ -n "$AFTER" ]] || { _error "cannot read the guests back after the ${VERB} : read them with proxmox_firewall.vm_ids.show_firewall.to.jsons.sh --table" ; exit 1 ; }
WANT=$([[ "$MODE" == guests-arm ]] && echo 1 || echo 0)
FAILED=0
while IFS= read -r G ; do
  [[ -z "$G" ]] && continue
  ID="$(printf '%s' "$G" | jq -r '.vm_id')"
  SUMMARY="$(printf '%s\n' "$AFTER" | jq -c --argjson id "$ID" --argjson want "$WANT" --arg action "$ACTION" --arg node "$NODE" --arg ssh "${SSH_STATE[$ID]:-unknown}" '
    [ inputs ] as $all
    | ($all | map(select(.vm_id == $id and .level == "card"))) as $cards
    | (($cards | map(.guest_enable) | first) // 0) as $switch
    | {
        action: $action,
        source: "proxmox",
        proxmox_node: $node,
        vm_id: $id,
        vm_name: (($cards | map(.vm_name) | first) // ""),
        guest_switch: (($switch | tostring) | tonumber? // 0),
        cards: [ $cards[] | .vm_network_device ],
        cards_as_asked: [ $cards[] | select(((.card_firewall_flag // 0) | tostring) == ($want | tostring)) | .vm_network_device ],
        ssh_accept: $ssh,
        filters: ($cards | any(.effectively_filtered == true))
      }
    | .as_asked = ((.guest_switch == $want) and ((.cards | length) == (.cards_as_asked | length)))' --null-input)"
  printf '%s\n' "$SUMMARY"
  [[ "$(printf '%s' "$SUMMARY" | jq -r '.as_asked')" == "true" ]] || FAILED=$((FAILED + 1))
done <<< "$TODO"

if [[ "$FAILED" -gt 0 ]]; then
  if [[ "$MODE" == guests-arm ]]; then _error "${FAILED} guest(s) are NOT set up to filter after the arming (switch or card flag not at 1) : read the summary lines above" ; else _error "${FAILED} guest(s) are STILL set up to filter after the disarming : read the summary lines above" ; fi
  exit 1
fi
