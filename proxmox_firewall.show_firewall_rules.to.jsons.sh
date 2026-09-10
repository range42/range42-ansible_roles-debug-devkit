#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_firewall.show_firewall_rules.to.jsons.sh
#
# The engine of the show_firewall_rules view : the rules of the datacenter, the rules of the node
# and, for every guest of the scope, the rules of its chain. It is the devkit behind
# `range42-context networks-show-firewall --rules`, usable on its own at any grain.
#
# THE TWO HOST LEVELS ALWAYS COME FIRST, whatever the scope, because they apply to everything :
# a guest chain is read after the datacenter chain and the node chain, in that order, which is
# also the order the concatenation follows on the host.
#
# THERE ARE NO RULES PER NETWORK CARD. A guest rule may name a card with iface, otherwise it holds
# for every card of the guest ; the card itself carries a switch, not rules, and that switch is
# what proxmox_firewall.show_firewall reports.
#
# One engine, six scopes, five wrappers named by the grain. The api fast path lives once, in
# proxmox_firewall.show_firewall_rules_with_api.to.jsons.sh ; this file delegates to it when the
# api answers and otherwise composes the existing readers (ansible path).
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="show_firewall_rules"
SOURCE_TAG="proxmox"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: THE ACTIVE SCENARIO (no stdin), THE WHOLE NODE, ONE GUEST"
  echo
  echo "    $(basename "$0") --table"
  echo "    $(basename "$0") --scope node --table"
  echo "    $(basename "$0") 2001"
  echo
  echo "  :: A SET OF GUESTS ON STDIN (plain ids or json lines)"
  echo
  local STDIN_JSON_DATA=(
    '{"vm_id":2001}'
    '{"vm_id":2002}'
  )
  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"' --json/'
  echo
  echo "    printf '2001\\n2002\\n' | $(basename "$0") --table"
  echo
  echo "  :: KEEP THE ANSIBLE PATH EVEN WHEN THE API ANSWERS"
  echo
  echo "    RANGE42_PROXMOX_API_FORCE=off $(basename "$0") --table"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the firewall rules of the datacenter, of the node and of the guests of a scope "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help]"
  echo "  [STDIN :: ids] | $(basename "$0") [--scope vm_id|vm_ids|scenario|node|dc|all] [--json|--text|--table] [vm_id]"
  echo
  echo "  --json     one json object per line (default)"
  echo "  --text     one line of words per json line"
  echo "  --table    one table per level of the firewall, then the guests without a rule, the absent ids, the errors"
  echo ""
  echo SCOPES
  echo
  echo "  vm_id      one guest : one id on stdin or as the argument"
  echo "  vm_ids     a set : one id per line on stdin, plain or json, duplicates folded, order kept"
  echo "  scenario   the vms of the active scenario, read in the workspace manifest"
  echo "  node       every guest the node runs, templates included"
  echo "  dc, all    the whole datacenter ; today the node of the vault, one node per workspace"
  echo
  echo "  The scope chooses the GUESTS. The rules of the datacenter and of the node are read whatever"
  echo "  the scope, because they apply to every guest. Without --scope : an argument means vm_id, ids"
  echo "  on stdin mean vm_ids, no stdin means scenario."
  echo ""
  echo LINES
  echo
  echo "  level dc_rule      one per rule of the datacenter chain : dc_fw_pos, dc_fw_action, dc_fw_type,"
  echo "                     dc_fw_iface, dc_fw_source, dc_fw_dest, dc_fw_proto, dc_fw_dport, dc_fw_sport,"
  echo "                     dc_fw_enable, dc_fw_comment, dc_fw_log ; a field the rule does not carry is absent"
  echo "  level node_rule    the same for the node chain, with the node_fw_ prefix"
  echo "  level guest_rule   the same for a guest chain, with the vm_fw_ prefix, plus vm_id and vm_name,"
  echo "                     plus THE VERDICT : vm_fw_in_force_on, the cards this rule is really in force"
  echo "                     on, and vm_fw_why_not, the named causes when it is in force nowhere"
  echo "  level guest        a guest the node runs whose chain holds no rule (rules: 0)"
  echo "  level absent       an id the node does not run"
  echo "  level error        a guest whose chain could not be read (reason)"
  echo
  echo "  A rule that grants nothing is not an accept : read dc_fw_enable and its friends, a disabled"
  echo "  rule still occupies its position. Exit 0 as soon as the two host levels could be read ;"
  echo "  absent, guest and error lines are data, not failures."
  echo ""
  echo "  THE VERDICT. A guest filters only when the datacenter switch, its own switch and the card"
  echo "  flag are all on. A rule naming a card by iface is in force on that card only ; a rule"
  echo "  without iface is in force on every card that filters. In force nowhere always comes with"
  echo "  its cause, never a bare no. It costs one more read per guest here, three on the api twin."
  echo ""
  echo PATHS
  echo
  echo "  When the api answers, this engine delegates to proxmox_firewall.show_firewall_rules_with_api.to.jsons.sh"
  echo "  (2 GET for the host levels, 1 for the guest list, 1 per guest). RANGE42_PROXMOX_API_FORCE=off keeps"
  echo "  the ansible path, which composes datacenter.list_iptables_rules, proxmox_node.list_iptables_rules,"
  echo "  proxmox_vm.list and, per guest, vm_id.list_iptables_rules. The same FIELDS on both paths, only source"
  echo "  differs ; the order of the keys inside an object is not part of the contract, the ansible path keeps"
  echo "  the order its readers publish rather than copying every field by hand and risking dropping one."
  echo ""
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the context guard runs first : both paths read the vault through the same link
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

# the request is read once here (options, stdin or manifest), then handed to whichever path runs
REQ=$(proxmox__inc.show_firewall.request.sh "$@")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# auto-delegate to the direct API fast path when reachable
# override with RANGE42_PROXMOX_API_FORCE=off to keep the ansible slow path
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ "${RANGE42_PROXMOX_API_FORCE:-auto}" != "off" ]]; then
  if proxmox__inc.api_reachable.sh ; then
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "proxmox API reachable - delegating to proxmox_firewall.show_firewall_rules_with_api.to.jsons.sh"
    exec proxmox_firewall.show_firewall_rules_with_api.to.jsons.sh --request "$REQ"
  else
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "proxmox API not reachable - using ansible slow path"
  fi
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the ansible slow path : the existing readers, composed. A reader prints nothing at all when the
# chain it read holds no rule (its print task carries a length guard), so an empty output and a
# failure are told apart by the return code, never by the silence.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT=$(printf '%s' "$REQ" | jq -r '.output')

_lines() { jq -c 'if type == "array" then .[] else . end' ; }

_json_only() {
  local l
  while IFS= read -r l ; do
    [ -n "${l//[[:space:]]/}" ] || continue
    printf '%s\n' "$l" | jq -e . >/dev/null 2>&1 && printf '%s\n' "$l"
  done
  return 0
}

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

_read() { # $1 = the devkit to call, rest = its stdin json ; prints its json lines, rc of the devkit
  local devkit="$1" payload="$2"
  set +e
  printf '%s\n' "$payload" | "$devkit" --json > "$TMP_DIR/raw" 2>/dev/null
  local rc=$?
  set -e
  _json_only < "$TMP_DIR/raw" | _lines
  return $rc
}

: > "$TMP_DIR/lines"

## the two host levels, always : without them there is nothing to report on
DC_RAW=$(_read proxmox_firewall.datacenter.list_iptables_rules.to.jsons.sh '{}') || {
  devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot read the datacenter firewall rules : nothing to report on" ; exit 1 ; }
ND_RAW=$(_read proxmox_firewall.proxmox_node.list_iptables_rules.to.jsons.sh '{}') || {
  devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot read the firewall rules of the node : nothing to report on" ; exit 1 ; }

## the node name : from a rule if there is one, else from the guest list below
NODE=$(printf '%s\n%s\n' "$DC_RAW" "$ND_RAW" | jq -r 'select(.proxmox_node != null) | .proxmox_node' 2>/dev/null | head -1)

GUESTS_RAW=$(_read proxmox_vm.list.to.jsons.sh '{}') || {
  devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot list the guests of the node : nothing to report on" ; exit 1 ; }
GUESTS=$(printf '%s\n' "$GUESTS_RAW" | jq -s -c '
  [ .[]
    | select(.vm_id != null)
    | {
        vm_id: (.vm_id | tonumber),
        vm_name: (.vm_name // "?"),
        vm_status: (.vm_status // "?"),
        vm_template: ((.vm_template // 0) | tostring | tonumber)
      }
  ]
  | sort_by(.vm_id)')
[[ -n "$NODE" ]] || NODE=$(printf '%s\n' "$GUESTS_RAW" | jq -r 'select(.proxmox_node != null) | .proxmox_node' | head -1)
[[ "$(printf '%s' "$GUESTS" | jq 'length')" -gt 0 ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot list the guests of the node : nothing to report on" ; exit 1 ; }

# a proxmox_node given on stdin is ignored : the node comes from the vault (one node per workspace)
while IFS= read -r other; do
  [[ -z "$other" || "$other" == "$NODE" ]] || devkit_utils.text.echo_trace.to.text.to.stderr.sh "proxmox_node ${other} given on stdin is ignored, the node comes from the vault : ${NODE}"
done < <(printf '%s' "$REQ" | jq -r '.stdin_nodes[]?')

## the readers already publish the twelve prefixed fields : only level and action are rewritten
_relevel() { # $1 = level
  jq -c --arg level "$1" --arg action "$ACTION" --arg src "$SOURCE_TAG" \
    '
      select(type == "object")
      | { level: $level }
      + .
      + {
          action: $action,
          source: $src
        }'
}

[ -n "${DC_RAW//[[:space:]]/}" ] && printf '%s\n' "$DC_RAW" | _relevel dc_rule >> "$TMP_DIR/lines"
[ -n "${ND_RAW//[[:space:]]/}" ] && printf '%s\n' "$ND_RAW" | _relevel node_rule >> "$TMP_DIR/lines"

IDS=$(printf '%s' "$REQ" | jq -c --argjson guests "$GUESTS" 'if .ids == null then ($guests | map(.vm_id)) else .ids end')

while IFS= read -r ID; do
  [[ -n "$ID" ]] || continue
  ENTRY=$(printf '%s' "$GUESTS" | jq -c --argjson id "$ID" 'first(.[] | select(.vm_id == $id)) // empty')
  if [[ -z "$ENTRY" ]]; then
    jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson id "$ID" \
      '
      {
        level: "absent",
        action: $action,
        source: $src,
        proxmox_node: $node,
        vm_id: $id
      }' >> "$TMP_DIR/lines"
    continue
  fi
  set +e
  VM_RAW=$(_read proxmox_firewall.vm_id.list_iptables_rules.to.jsons.sh "$(printf '{"vm_id":%s}' "$ID")")
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson id "$ID" --arg reason "the per-vm reader failed (rc ${rc})" \
      '
      {
        level: "error",
        action: $action,
        source: $src,
        proxmox_node: $node,
        vm_id: $id,
        reason: $reason
      }' >> "$TMP_DIR/lines"
    continue
  fi
  if [[ -z "${VM_RAW//[[:space:]]/}" ]]; then
    printf '%s' "$ENTRY" | jq -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" \
      '
      { level: "guest",
        action: $action,
        source: $src,
        proxmox_node: $node
      }
      + .
      + { rules: 0 }' >> "$TMP_DIR/lines"
    continue
  fi
  ## THE VERDICT, per card. Same reader as the switches view, so the two views cannot disagree : it
  ## publishes one line per card with the three switches, the card flag, effectively_filtered and
  ## the named causes. A reader that fails leaves the verdict unknown, it never invents a yes.
  set +e
  CARDS_RAW=$(_read proxmox_firewall.vm_id.effective_filtering_state.to.jsons.sh "$(printf '{"vm_id":%s}' "$ID")")
  crc=$?
  set -e
  if [[ "$crc" -ne 0 ]]; then
    FORCE=$(jq -n -c '{ by_card: {}, filtered: [], why_not: ["the per-card verdict is unreadable"] }')
  else
    FORCE=$(printf '%s\n' "$CARDS_RAW" | jq -s -c '
      [ .[] | select(type == "object" and .vm_network_device != null) ] as $cards
      | {
          by_card: ( [ $cards[]
                       | { key: .vm_network_device,
                           value: {
                             filtered: (.effectively_filtered == true),
                             why_not: (.missing // [])
                           }
                         }
                     ] | from_entries ),
          filtered: [ $cards[] | select(.effectively_filtered == true) | .vm_network_device ],
          why_not: ( if ($cards | length) == 0 then
                       ["no network card"]
                     else
                       ( ["datacenter_enable", "guest_enable", "card_firewall_flag"] as $order
                       | ( [ $cards[] | (.missing // [])[] ] | unique ) as $seen
                       | ( [ $order[] | select(IN($seen[])) ] + [ $seen[] | select(IN($order[]) | not) ] ) )
                     end )
        }')
  fi

  # vm_id is taken back from $e, NOT from the reader : the reader echoes the id as it received it, a
  # string, while the api twin publishes the number of the guest list. The contract is the same
  # fields AND the same types on both paths, so the numeric id of the guest list wins here too.
  printf '%s\n' "$VM_RAW" | jq -c --arg level guest_rule --arg action "$ACTION" --arg src "$SOURCE_TAG" --argjson e "$ENTRY" --argjson f "$FORCE" \
    '
      ## a rule naming a card by iface holds for that card only ; a rule without iface holds for
      ## every card that filters. The cause is named, so a rule that grants nothing says why.
      select(type == "object")
      | (.vm_fw_iface // null) as $iface
      | ( if $iface == null then
            $f.filtered
          elif ($f.by_card[$iface].filtered // false) then
            [ $iface ]
          else
            []
          end ) as $on
      | ( if ($on | length) > 0 then
            []
          elif $iface == null then
            $f.why_not
          else
            ($f.by_card[$iface].why_not // ["no card named " + $iface])
          end ) as $why
      | { level: $level }
      + .
      + {
          action: $action,
          source: $src,
          vm_id: $e.vm_id,
          vm_name: $e.vm_name,
          vm_status: $e.vm_status,
          vm_template: $e.vm_template,
          vm_fw_in_force_on: $on,
          vm_fw_why_not: $why
        }' >> "$TMP_DIR/lines"
done < <(printf '%s' "$IDS" | jq -r '.[]')

# the guest table is titled with the perimeter that was ASKED : at scope node a guest with an empty
# chain only shows in the line below the table, so the rows alone say nothing about the perimeter
GUESTS_LABEL=$(printf '%s' "$REQ" | jq -r --arg node "$NODE" '
  if .scope == "scenario" then
    "scenario: " + (.scenario_name // "?")
  elif .scope == "vm_id" then
    (.ids[0] | tostring)
  elif .scope == "vm_ids" then
    ((.ids | length | tostring) + " ids on stdin")
  elif .scope == "node" then
    ("node " + $node + " : every guest")
  else
    "datacenter : every guest"
  end')

proxmox__inc.show_firewall_rules.render.sh "$OUTPUT" "$GUESTS_LABEL" < "$TMP_DIR/lines"
