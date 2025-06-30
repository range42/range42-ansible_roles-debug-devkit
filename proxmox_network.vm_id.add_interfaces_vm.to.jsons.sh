#!/bin/bash

# ISSUE -102

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="network_add_interfaces_vm"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"100\" | $(basename "$0") "
  echo "    echo \"101\" | $(basename "$0") --json"
  echo "    echo \"102\" | $(basename "$0") --text"
  echo
  echo "    cat /tmp/proxmox_nodes.text | $(basename "$0")"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{ "vm_id":100, "iface_model":"virtio","iface_bridge":"vmbr0"}'
    '{ "vm_id":100, "vm_vmnet_id": 7, "iface_model":"virtio", "iface_bridge":"vmbr0" }'
    '{ "proxmox_node":"px-testing", "vm_id":100, "net_index": 7, "iface_model":"virtio", "iface_bridge":"vmbr0" }'

  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") vmbr0 --json"

  echo ""
  echo "    cat /tmp/proxmox_nodes.json | $(basename "$0")"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo
  echo
  echo NAME
  echo "  $(basename "$0") - add VM network interfaces - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  $(basename "$0") [--json]                                   - force output as json "
  echo "  $(basename "$0") [partial_or_complete_bridge_name] [--json] - Force output in JSON format with a case insensitive filter on vm_network_bridge "
  echo "  $(basename "$0") [--text]                                   - force output as text (debug purpose)"
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
# - look for output types or filter on vm_name
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

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR::iface_model" "STR::iface_bridge" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  # printf "%s\n" "$JSON_LINE_REQ"  | jq "."

  IS_VM_VMNET=$(jq -r '.vm_vmnet_id // empty' <<<"$CURRENT_JSON_LINE")

  if [[ -z "$IS_VM_VMNET" ]]; then # missing vmnet_id ?

    IS_VM_VMNET=$(printf '%s\n' "$JSON_LINE_REQ" |
      proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh |
      wc -l)
  fi
  NEW_CURRENT_JSON_LINE=$(printf '%s\n' "$CURRENT_JSON_LINE" | jq -c --arg jq_vm_vmnet_id "$IS_VM_VMNET" '. + {  ("vm_vmnet_id"): $jq_vm_vmnet_id } ')

  CURRENT_JSON_LINE=$NEW_CURRENT_JSON_LINE
  devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"

  if [[ "$OUTPUT_JSON" == true ]]; then # json mode.

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION"

  else
    # text output mode  - debug

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
