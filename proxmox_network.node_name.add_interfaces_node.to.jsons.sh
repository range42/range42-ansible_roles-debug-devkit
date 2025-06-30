#!/bin/bash

# ISSUE -101

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="network_add_interfaces_node"
DEFAULT_OUTPUT_JSON=true

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
    '{"proxmox_node":"px-testing","iface_name":"vmbr42","iface_type":"bridge","bridge_ports":"enp87s0"}'
    '{"proxmox_node":"px-testing","iface_name":"vmbr42","iface_type":"bridge","bridge_ports":"enp87s0", "iface_autostart":1,"ip_address":"192.168.88.2", "ip_netmask":"255.255.255.0" }'
    '{"proxmox_node":"px-testing","iface_name":"vmbr42","iface_type":"bridge","bridge_ports":"enp87s0", "iface_autostart":1,"ip_address":"192.168.88.2", "ip_netmask":"255.255.255.0", "ip_gateway":"192.168.88.1" }'
    '{"proxmox_node":"px-testing","iface_name":"vmbr42","iface_type":"OVSBridge","ovs_bridge":"enp87s0","iface_autostart":1,"ip_address":"192.168.88.2","ip_netmask":"255.255.255.0"}'
    #
    ''
    '{"iface_name":"bridge42","iface_type":"bridge","iface_autostart":1}'
    '{"iface_name":"bond","iface_type":"bond","iface_autostart":1}'
    '{"iface_name":"alias","iface_type":"alias","iface_autostart":1}'
    '{"iface_name":"vlan","iface_type":"vlan","iface_autostart":1}'
    '{"iface_name":"ovsbridge42","iface_type":"OVSBridge","iface_autostart":1}'
    '{"iface_name":"ovsbond42","iface_type":"OVSBond","iface_autostart":1}'
    '{"iface_name":"ovsport42","iface_type":"OVSPort","iface_autostart":1}'
    '{"iface_name":"ovintport42","iface_type":"OVSIntPort","iface_autostart":1}'
    '{"iface_name":"vmnet42","iface_type":"vnet","iface_autostart":1}'

  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --text"

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
  *) ;;
    # if [[ -z "$ARG_VM_BRIDGE_NAME_FILTER" ]]; then
    #   ARG_VM_BRIDGE_NAME_FILTER="$1"
    #   shift
    # else
    #   devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
    #   show_example
    #   exit 1
    # fi
    # ;;
  esac
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::iface_name" "STR::iface_type" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# IFS=$'\n'

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"
  # exit 1

  if [[ "$OUTPUT_JSON" == true ]]; then # json mode.

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION"

    # jq ".[]"
    # fi

  else # text output mode  - debug

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
