#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_vm_list_options"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"vm_id":VM_ID,"proxmox_node":"NODE_NAME"}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --json"

  echo ""
  echo ""
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Report the FOUR firewall levels of a guest and whether it is actually filtered "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help] "
  echo "  STDIN :: JSON | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: JSON | $(basename "$0") [--text]    - force output as text"
  echo ""
  echo "REQUIRED FIELDS"
  echo
  echo "  proxmox_node        the node the guest runs on"
  echo "  vm_id               the guest to report on"
  echo ""
  echo "OPTIONAL FIELDS"
  echo
  echo "  none : this wrapper only reads"
  echo ""
  echo "WHY FOUR LEVELS AND NOT THREE"
  echo
  echo "  Three switches live in the api options : datacenter, node and guest. A fourth lives"
  echo "  on the network card itself, as firewall=1 in the guest config. Measured : with the"
  echo "  card flag absent, NOTHING is filtered even with the three others enabled. The card"
  echo "  flag is the only one that filters, so reading the three options alone answers a"
  echo "  different question than the one an operator is asking."
  echo
  echo "  This wrapper reads all four and says which ones are off, per card."
  echo ""
  echo "READING THE OUTPUT"
  echo
  echo "  One line per network card. effectively_filtered is true only when all four are on."
  echo "  missing lists the ones that are not, so the answer is actionable rather than a"
  echo "  verdict with no cause. card_firewall_flag is absent when the card carries no flag,"
  echo "  which is not the same as a flag set to zero."
  echo ""
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh
proxmox__inc.warmup_checks_stdin.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# define output type
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

case "${1:-}" in
--json)
  OUTPUT_JSON=true
  ;;
--text)
  OUTPUT_JSON=false
  ;;
"") ;;
*)
  devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
  show_example
  exit 1
  ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# Each reader is called once and its output is reduced to the LAST valid json object, so a
# warmup line or a debug line on the way cannot be mistaken for the payload.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

_lines() { jq -c 'if type=="array" then .[] else . end' ; }

# So the two concerns are separated : keep only the lines that ARE json, then normalise shape.
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

INPUT_JSON=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh \
  "INT::vm_id" \
  "STR::proxmox_node" \
  "STR::action")

DC_JSON=$(printf '%s\n' "$INPUT_JSON" | proxmox_firewall.datacenter.list_options.to.jsons.sh --json | _last_object)
ND_JSON=$(printf '%s\n' "$INPUT_JSON" | proxmox_firewall.proxmox_node.list_options.to.jsons.sh --json | _last_object)
VM_JSON=$(printf '%s\n' "$INPUT_JSON" | proxmox_firewall.vm_id.list_options.to.jsons.sh --json | _last_object)
CARDS_JSON=$(printf '%s\n' "$INPUT_JSON" | proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh --json | _json_only | _lines || true)

if [ -z "${CARDS_JSON//[[:space:]]/}" ]; then
  devkit_utils.text.echo_error.to.text.to.stderr.sh "the guest reports no network card : nothing to report on."
  exit 0
fi

REPORT=$(printf '%s\n' "$CARDS_JSON" | jq -s -c \
  --argjson dc "$DC_JSON" \
  --argjson nd "$ND_JSON" \
  --argjson vm "$VM_JSON" \
  '
  def on($v): ($v != null) and (($v | tostring) != "0") and (($v | tostring) != "");
  ($dc.dc_fw_opt_enable)   as $d |
  ($nd.node_fw_opt_enable) as $n |
  ($vm.vm_fw_opt_enable)   as $g |
  .[] |
  . as $card |
  ($card.vm_network_firewall) as $f |
  {
    action:               "firewall_effective_filtering_state",
    source:               "proxmox",
    proxmox_node:         $card.proxmox_node,
    vm_id:                $card.vm_id,
    vm_network_device:    $card.vm_network_device,
    vm_network_bridge:    $card.vm_network_bridge,
    datacenter_enable:    $d,
    node_enable:          $n,
    guest_enable:         $g,
    card_firewall_flag:   $f,
    effectively_filtered: (on($d) and on($n) and on($g) and on($f)),
    missing: (
      (if on($d) then [] else ["datacenter_enable"] end) +
      (if on($n) then [] else ["node_enable"] end) +
      (if on($g) then [] else ["guest_enable"] end) +
      (if on($f) then [] else ["card_firewall_flag"] end)
    )
  }
  ')

if [[ "$OUTPUT_JSON" == true ]]; then
  printf '%s\n' "$REPORT"
else
  printf '%s\n' "$REPORT" | jq -r '
    "\(.vm_network_device)  bridge=\(.vm_network_bridge // "?")  dc=\(.datacenter_enable // "-")  node=\(.node_enable // "-")  guest=\(.guest_enable // "-")  card=\(.card_firewall_flag // "-")  filtered=\(.effectively_filtered)" +
    (if (.missing | length) > 0 then "   off: \(.missing | join(", "))" else "" end)'
fi
