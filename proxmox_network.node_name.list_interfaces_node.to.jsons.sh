#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="network_list_interfaces_node"
DEFAULT_OUTPUT_JSON=true
ARG_VM_BRIDGE_NAME_FILTER=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"px-testing\" | $(basename "$0") "
  echo "    echo \"px-testing\" | $(basename "$0") --json"
  echo "    echo \"px-testing\" | $(basename "$0") --text"
  echo
  echo "    cat /tmp/px_nodes.text | $(basename "$0")"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"proxmox_node":"px-testing"}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") local --json"

  echo ""
  echo "    cat /tmp/px_nodes.json | $(basename "$0")"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - list NODE network interfaces - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  $(basename "$0") [--json]                               - force output as json "
  echo "  $(basename "$0") [partial_or_complete_iface] [--json] - Force output in JSON format with a case insensitive filter on iface "
  echo "  $(basename "$0") [--text]                               - force output as text (debug purpose)"
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
  *)
    if [[ -z "$ARG_VM_BRIDGE_NAME_FILTER" ]]; then
      ARG_VM_BRIDGE_NAME_FILTER="$1"
      shift
    else
      devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
      show_example
      exit 1
    fi
    ;;
  esac
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# IFS=$'\n'

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r NODE_JSON; do

  if [[ "$OUTPUT_JSON" == true ]]; then # json mode.

    if [[ -n "$ARG_VM_BRIDGE_NAME_FILTER" ]]; then # check if filter provided in argument

      printf '%s\n' "$NODE_JSON" |
        proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" |
        jq -c ".[]" |
        devkit_transform.jsons.key_field_greper.to.jsons.sh "iface" "$ARG_VM_BRIDGE_NAME_FILTER"

    else # not filter in argument
      printf '%s\n' "$NODE_JSON" |
        proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" |
        jq ".[]"
    fi

  else # text output mode  - debug

    printf '%s\n' "$NODE_JSON" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
