#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# update an SDN subnet, the snat toggle
#
# >>> sdn_subnet_id IS THE ID, NOT THE CIDR <<<
# <zone>-<network>-<mask>, for instance r42test-192.168.199.0-24. The role asserts it and
# refuses anything containing a slash.
#
# sdn_subnet_snat is required here on purpose : this devkit IS the toggle, and an update
# carrying no field would be a silent no-op. The role itself accepts more fields.
#
# >>> THE TOGGLE IS THREE STEPS <<<
#   1. this devkit          the declaration changes
#   2. apply_sdn            the change becomes live
#   3. delete_extra_snat_rules   the live SNAT rules are reconciled
# Step 3 is not optional in either direction : snat=0 orphans the live rule, so without it
# a subnet set to 0 keeps its internet access.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="network_update_sdn_subnet"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"proxmox_node":"px-testing","sdn_vnet":"net199","sdn_subnet_id":"r42zone-192.168.199.0-24","sdn_subnet_snat":1}'
    '{"proxmox_node":"px-testing","sdn_vnet":"net199","sdn_subnet_id":"r42zone-192.168.199.0-24","sdn_subnet_snat":0}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --text"

  echo ""
  echo "    cat /tmp/sdn_requests.json | $(basename "$0")"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - update an SDN subnet, the snat toggle - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  $(basename "$0") [--json]      - force output as json "
  echo "  $(basename "$0") [--text]      - force output as text (debug purpose)"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# browse provided arugments :
#

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    OUTPUT_JSON=true
    shift
    ;;
  --text)
    OUTPUT_JSON=false
    shift
    ;;
  -*)
    devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
    show_example
    exit 1
    ;;
  *) ;;
  esac
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# Every key below is REQUIRED : a write action with a missing field either fails on
# the API side with an unhelpful message, or worse, succeeds having changed nothing.
#
JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::sdn_vnet" "STR::sdn_subnet_id" "STR::sdn_subnet_snat" "STR::proxmox_node" "STR::action")
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"

  if [[ "$OUTPUT_JSON" == true ]]; then # json mode.

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION"

  else # text output mode  - debug

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
