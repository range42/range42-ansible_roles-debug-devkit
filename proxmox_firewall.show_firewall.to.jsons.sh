#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_firewall.show_firewall.to.jsons.sh
#
# The engine of the show_firewall view : the three host switches and, for every guest of the
# scope, one line per network card saying whether that card is actually filtered. It is the
# devkit behind `range42-context networks-show-firewall`, usable on its own at any grain.
#
# One engine, six scopes, five wrappers named by the grain (vm_id, vm_ids, scenario,
# proxmox_node, datacenter) that only exec this file with their --scope. The api fast path
# lives once, in proxmox_firewall.show_firewall_with_api.to.jsons.sh ; this file delegates
# to it when the api answers and otherwise composes the existing readers (ansible path).
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="show_firewall"
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
  echo "  $(basename "$0") - the show_firewall view : host switches and, per guest, one line per card with a verdict "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help]"
  echo "  [STDIN :: ids] | $(basename "$0") [--scope vm_id|vm_ids|scenario|node|dc|all] [--json|--text|--table] [vm_id]"
  echo
  echo "  --json     one json object per line (default)"
  echo "  --text     one line of words per json line"
  echo "  --table    the host sentence, a table of the cards, then the guests without a card, the absent ids, the errors"
  echo ""
  echo SCOPES
  echo
  echo "  vm_id      one guest : one id on stdin or as the argument"
  echo "  vm_ids     a set : one id per line on stdin, plain or json, duplicates folded, order kept"
  echo "  scenario   the vms of the active scenario, read in the workspace manifest (RANGE42_ACTIVE_CONFIG_DIR/scenario/manifest/scenario_vms.json)"
  echo "  node       every guest the node runs, templates included (vm_template tells them apart)"
  echo "  dc, all    the whole datacenter ; today the node of the vault, one node per workspace"
  echo
  echo "  Without --scope : an argument means vm_id, ids on stdin mean vm_ids, no stdin means scenario."
  echo "  The node and the api token come from the vault ; a proxmox_node given on stdin is ignored with a trace."
  echo ""
  echo LINES
  echo
  echo "  level host     once, first : proxmox_node, datacenter_enable, node_enable"
  echo "  level card     one per network card of a guest the node runs : vm_id, vm_name, vm_status, vm_template,"
  echo "                 vm_network_device, vm_network_bridge, datacenter_enable, node_enable, guest_enable,"
  echo "                 card_firewall_flag, effectively_filtered, missing"
  echo "  level guest    a guest the node runs that has no network card (cards: 0)"
  echo "  level absent   an id the node does not run"
  echo "  level error    a guest the node runs whose options or config could not be read (reason)"
  echo
  echo "  A switch or a flag is 1, 0, or null when it was never set : null is not 0. The verdict"
  echo "  effectively_filtered needs the datacenter switch, the guest switch and the card flag ; the node"
  echo "  switch is reported and never enters the verdict. Exit 0 as soon as the host could be read ;"
  echo "  absent, guest and error lines are data, not failures."
  echo ""
  echo PATHS
  echo
  echo "  When the api answers, this engine delegates to proxmox_firewall.show_firewall_with_api.to.jsons.sh"
  echo "  (3 GET for the host, 2 per guest). RANGE42_PROXMOX_API_FORCE=off keeps the ansible path, which"
  echo "  composes datacenter.list_options, proxmox_node.list_options, proxmox_vm.list and, per guest,"
  echo "  vm_id.effective_filtering_state. Same lines on both paths, only source differs."
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
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "proxmox API reachable - delegating to proxmox_firewall.show_firewall_with_api.to.jsons.sh"
    exec proxmox_firewall.show_firewall_with_api.to.jsons.sh --request "$REQ"
  else
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "proxmox API not reachable - using ansible slow path"
  fi
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the ansible slow path : the existing readers, composed. Each reader is reduced to its LAST
# valid json object, so a warmup line or a debug line on the way cannot be mistaken for the
# payload (same care as proxmox_firewall.vm_id.effective_filtering_state).
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

_last_object() {
  local out
  out=$(_json_only | _lines 2>/dev/null || true)
  [ -n "${out//[[:space:]]/}" ] || { printf '{}\n' ; return 0 ; }
  printf '%s\n' "$out" | tail -1
}

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# the host : an empty object on stdin makes the readers take the node from the vault
DC_JSON=$(printf '{}\n' | proxmox_firewall.datacenter.list_options.to.jsons.sh --json 2>/dev/null | _last_object || true)
ND_JSON=$(printf '{}\n' | proxmox_firewall.proxmox_node.list_options.to.jsons.sh --json 2>/dev/null | _last_object || true)
NODE=$(printf '%s' "$DC_JSON" | jq -r '.proxmox_node // empty')
[[ -n "$NODE" ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot read the datacenter firewall options : nothing to report on" ; exit 1 ; }
[[ "$(printf '%s' "$ND_JSON" | jq -r '.proxmox_node // empty')" == "$NODE" ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot read the firewall options of node ${NODE} : nothing to report on" ; exit 1 ; }
DC_ENABLE=$(printf '%s' "$DC_JSON" | jq -c '.dc_fw_opt_enable // null')
ND_ENABLE=$(printf '%s' "$ND_JSON" | jq -c '.node_fw_opt_enable // null')

GUESTS=$( { printf '{}\n' | proxmox_vm.list.to.jsons.sh --json 2>/dev/null || true ; } | _json_only | _lines \
  | jq -s -c '[.[] | select(.vm_id != null) | {vm_id: (.vm_id | tonumber), vm_name: (.vm_name // "?"), vm_status: (.vm_status // "?"), vm_template: ((.vm_template // 0) | tostring | tonumber)}] | sort_by(.vm_id)')
[[ "$(printf '%s' "$GUESTS" | jq 'length')" -gt 0 ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot list the guests of node ${NODE} : nothing to report on" ; exit 1 ; }

# a proxmox_node given on stdin is ignored : the node comes from the vault (one node per workspace)
while IFS= read -r other; do
  [[ -z "$other" || "$other" == "$NODE" ]] || devkit_utils.text.echo_trace.to.text.to.stderr.sh "proxmox_node ${other} given on stdin is ignored, the node comes from the vault : ${NODE}"
done < <(printf '%s' "$REQ" | jq -r '.stdin_nodes[]?')

IDS=$(printf '%s' "$REQ" | jq -c --argjson guests "$GUESTS" 'if .ids == null then ($guests | map(.vm_id)) else .ids end')

JQ_DEFS='def sw: if . == null then null else (tostring | tonumber) end;
         def on: (. != null) and ((. | tostring) != "0") and ((. | tostring) != "");'

emit() { printf '%s\n' "$1" >> "$TMP_DIR/lines" ; }
: > "$TMP_DIR/lines"

emit "$(jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson dc "$DC_ENABLE" --argjson nd "$ND_ENABLE" \
  "$JQ_DEFS"'{level: "host", action: $action, source: $src, proxmox_node: $node, datacenter_enable: ($dc | sw), node_enable: ($nd | sw)}')"

while IFS= read -r ID; do
  [[ -n "$ID" ]] || continue
  ENTRY=$(printf '%s' "$GUESTS" | jq -c --argjson id "$ID" 'first(.[] | select(.vm_id == $id)) // empty')
  if [[ -z "$ENTRY" ]]; then
    emit "$(jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson id "$ID" \
      '{level: "absent", action: $action, source: $src, proxmox_node: $node, vm_id: $id}')"
    continue
  fi

  # the per-vm reader : one line per card, nothing for a guest without a card, a failure when it cannot read
  set +e
  printf '{"vm_id":%s}\n' "$ID" | proxmox_firewall.vm_id.effective_filtering_state.to.jsons.sh --json > "$TMP_DIR/cards.raw" 2>/dev/null
  RC=$?
  set -e
  CARDS=$(_json_only < "$TMP_DIR/cards.raw" | _lines)
  if [[ "$RC" -ne 0 ]]; then
    emit "$(jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson id "$ID" --arg reason "the per-vm reader failed (rc ${RC})" \
      '{level: "error", action: $action, source: $src, proxmox_node: $node, vm_id: $id, reason: $reason}')"
    continue
  fi

  if [[ -z "${CARDS//[[:space:]]/}" ]]; then
    G_ENABLE=$(printf '{"vm_id":%s}\n' "$ID" | proxmox_firewall.vm_id.list_options.to.jsons.sh --json 2>/dev/null | _last_object | jq -c '.vm_fw_opt_enable // null')
    emit "$(jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson entry "$ENTRY" --argjson dc "$DC_ENABLE" --argjson nd "$ND_ENABLE" --argjson g "$G_ENABLE" \
      "$JQ_DEFS"'{level: "guest", action: $action, source: $src, proxmox_node: $node,
        vm_id: $entry.vm_id, vm_name: $entry.vm_name, vm_status: $entry.vm_status, vm_template: $entry.vm_template,
        datacenter_enable: ($dc | sw), node_enable: ($nd | sw), guest_enable: ($g | sw),
        cards: 0, effectively_filtered: false, missing: ["no network card"]}')"
    continue
  fi

  printf '%s\n' "$CARDS" | jq -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson entry "$ENTRY" \
    "$JQ_DEFS"'
    (.datacenter_enable | sw) as $d | (.node_enable | sw) as $n | (.guest_enable | sw) as $ge | (.card_firewall_flag | sw) as $f |
    {level: "card", action: $action, source: $src, proxmox_node: $node,
     vm_id: $entry.vm_id, vm_name: $entry.vm_name, vm_status: $entry.vm_status, vm_template: $entry.vm_template,
     vm_network_device: .vm_network_device, vm_network_bridge: (.vm_network_bridge // null),
     datacenter_enable: $d, node_enable: $n, guest_enable: $ge, card_firewall_flag: $f,
     node_enable_is_informational: true,
     effectively_filtered: (($d | on) and ($ge | on) and ($f | on)),
     missing: ((if ($d | on) then [] else ["datacenter_enable"] end)
             + (if ($ge | on) then [] else ["guest_enable"] end)
             + (if ($f | on) then [] else ["card_firewall_flag"] end))}' >> "$TMP_DIR/lines"
done < <(printf '%s' "$IDS" | jq -r '.[]')

proxmox__inc.show_firewall.render.sh "$OUTPUT" < "$TMP_DIR/lines"
