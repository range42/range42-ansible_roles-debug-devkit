#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_dc_delete_iptables_rule"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"proxmox_node":"NODE_NAME"}'
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
  echo "  $(basename "$0") - Delete ALL iptables rules - datacenter firewall - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help] "
  echo "  STDIN :: JSON | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: JSON | $(basename "$0") [--text]    - force output as text"
  echo ""
  echo "REQUIRED FIELDS"
  echo
  echo "  proxmox_node   the node the api call is made against"
  echo ""
  echo "OPTIONAL FIELDS"
  echo
  echo "  none : this composite reads the chain itself and needs no position"
  echo ""
  echo "  WHAT THIS DOES NOT DO"
  echo "  "
  echo "    It empties the chain. Every rule goes, including any management accept that"
  echo "    keeps this level reachable. Nothing here refuses, so read the chain first if"
  echo "    you are not certain what it holds."
  echo "  "
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
# ONE AT A TIME, RE-READING THE CHAIN BEFORE EVERY DELETE.
#
# A rule is addressed by its POSITION, and the api RENUMBERS the chain after every delete.
# Any approach that reads the chain once and then works through the positions it saw is
# working from ranks that stopped being true after the first delete. Measured on a chain of
# two identical rules handled that way : one deleted, the survivor renumbered to position 0
# and never touched.
#
# So the chain is read again at the top of every round, one rule is deleted, and the loop
# starts over. Positions are therefore never older than the call that uses them. This costs
# one api round trip per rule, which is the price of not guessing.
#
# A bound is required, not optional : if a delete fails without saying so, the rule stays,
# matches again, and the loop runs forever. The bound is the initial count plus a margin,
# and falling through it is an error that names how many rules are left.
#
# The remaining window is between this round's read and this round's delete. It is
# milliseconds rather than however long since an operator last looked, and closing it
# entirely would need the api's digest guard, which is not used anywhere in this project yet.
#
# The alias equivalent needs none of this : an alias is addressed by NAME, and a name does
# not move when a neighbour disappears.
#

INPUT_JSON=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

FIRST_READ=$(printf '%s\n' "$INPUT_JSON" | proxmox_firewall.datacenter.list_iptables_rules.to.jsons.sh)
TOTAL=$(printf '%s\n' "$FIRST_READ" | grep -c . || true)

if [ "$TOTAL" -eq 0 ]; then
  devkit_utils.text.echo_error.to.text.to.stderr.sh "the chain is already empty : nothing to delete."
  exit 0
fi

BOUND=$((TOTAL + 2))
ROUND=0
DELETED=0

while : ; do

  ROUND=$((ROUND + 1))

  if [ "$ROUND" -gt "$BOUND" ]; then
    REMAINING=$(printf '%s\n' "$INPUT_JSON" | proxmox_firewall.datacenter.list_iptables_rules.to.jsons.sh | grep -c . || true)
    devkit_utils.text.echo_error.to.text.to.stderr.sh "did not converge after ${BOUND} rounds, ${REMAINING} rule(s) still present : refusing to keep looping."
    exit 1
  fi

  TARGET=$(printf '%s\n' "$INPUT_JSON" | proxmox_firewall.datacenter.list_iptables_rules.to.jsons.sh | jq -s -c 'if length == 0 then empty else .[0] end')

  [ -n "${TARGET//[[:space:]]/}" ] || break

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$TARGET" |
      jq -c '{ proxmox_node, dc_fw_pos }' |
      proxmox_firewall.datacenter.delete_iptables_rules.to.jsons.sh --json

  else

    printf '%s\n' "$TARGET" |
      jq -c '{ proxmox_node, dc_fw_pos }' |
      proxmox_firewall.datacenter.delete_iptables_rules.to.jsons.sh --text

  fi

  DELETED=$((DELETED + 1))

done

devkit_utils.text.echo_error.to.text.to.stderr.sh "deleted ${DELETED} rule(s) of the ${TOTAL} present at the first read, chain now empty."
