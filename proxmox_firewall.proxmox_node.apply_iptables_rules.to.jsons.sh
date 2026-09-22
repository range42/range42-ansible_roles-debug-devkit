#!/bin/bash

#
# Apply ONE firewall rule on ONE NODE.
#
# TWO FIELDS ARE WORTH PASSING EXPLICITLY
# node_fw_pos : NOT ACCEPTED ANY MORE. PVE inserts at the TOP of the chain and ignores
#             any position asked for, measured four times the 2026-08-28. Read the chain
#             back with the list action to know where a rule landed. The delete action
#             keeps its position : DELETE by position is the only call the API offers.
# node_fw_enable : without it the rule is stored DISABLED. It appears in the configuration,
#             it reads as present, and it grants nothing. Measured the 2026-08-27.
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_node_apply_iptables_rule"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"100\" | $(basename "$0") "
  echo "    echo \"101\" | $(basename "$0") --json"
  echo "    echo \"102\" | $(basename "$0") --text"
  echo
  echo "    cat /tmp/vm_id.text | $(basename "$0")"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local DEFAULT_STDIN_JSON_DATA=(
    # INPUT
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"DROP","node_fw_type":"in","node_fw_enable":1}'
    # OUTPUT
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"80","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"443","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"53","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"DROP","node_fw_type":"out","node_fw_enable":1}'

  )

  local STDIN_JSON_DATA=(
    #
    \
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_log":"alert","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_log":"warning","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_log":"info","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_log":"alert","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_log":"warning","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_log":"info","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"80","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"80","node_fw_log":"alert","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"80","node_fw_log":"warning","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"80","node_fw_log":"info","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"80","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"80","node_fw_log":"alert","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"80","node_fw_log":"warning","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"80","node_fw_log":"info","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"443","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"443","node_fw_log":"alert","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"443","node_fw_log":"warning","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"tcp","node_fw_dport":"443","node_fw_log":"info","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"443","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"443","node_fw_log":"alert","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"443","node_fw_log":"warning","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"tcp","node_fw_dport":"443","node_fw_log":"info","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"udp","node_fw_dport":"53","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"udp","node_fw_dport":"53","node_fw_log":"alert","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"udp","node_fw_dport":"53","node_fw_log":"warning","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_proto":"udp","node_fw_dport":"53","node_fw_log":"info","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"udp","node_fw_dport":"53","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"udp","node_fw_dport":"53","node_fw_log":"alert","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"udp","node_fw_dport":"53","node_fw_log":"warning","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"out","node_fw_iface":"net0","node_fw_proto":"udp","node_fw_dport":"53","node_fw_log":"info","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"DROP","node_fw_type":"in","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"DROP","node_fw_type":"in","node_fw_log":"alert","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"DROP","node_fw_type":"in","node_fw_log":"warning","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"DROP","node_fw_type":"in","node_fw_log":"info","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"DROP","node_fw_type":"in","node_fw_iface":"net0","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"DROP","node_fw_type":"in","node_fw_iface":"net0","node_fw_log":"alert","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"DROP","node_fw_type":"in","node_fw_iface":"net0","node_fw_log":"warning","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"DROP","node_fw_type":"in","node_fw_iface":"net0","node_fw_log":"info","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1,"node_fw_source":"192.168.1.0/24"}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1,"node_fw_dest":"0.0.0.0/0"}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1,"node_fw_sport":"1024"}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1,"node_fw_comment":"TEST COMMENT"}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1,"node_fw_comment":"ABCD1234 - 123123"}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1,"node_fw_log":"info"}'
    '{"vm_id":100,"node_fw_action":"ACCEPT","node_fw_type":"in","node_fw_proto":"tcp","node_fw_dport":"22","node_fw_enable":1,"node_fw_iface":"net0","node_fw_source":"192.168.1.0/24","node_fw_dest":"0.0.0.0/0","node_fw_sport":"1024","node_fw_comment":"Test comment","node_fw_log":"DEBUG"}'

    #

  )
  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --json"

  echo ""
  echo ""
  echo ""
  # echo "    cat /tmp/vm_list.json | $(basename "$0")"
  # echo
  # # echo "    proxmox_vm.list.to.jsons.sh          | jq -r '.vm_id' | $(basename "$0")"
  # # echo "    proxmox_vm.list.to.jsons.sh group_02 | jq -r '.vm_id' | $(basename "$0")"

  for json in "${DEFAULT_STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  echo ""
  echo '  cat ./examples/firewall_vm_default_rules.json | jq -c "." |  '"$(basename "$0")"''

  echo ""
  echo "other examples : "
  echo ""
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Apply iptables rules - node firewall - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                     $(basename "$0") [-h|--help] "
  echo "  STDIN :: [VM_ID] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [VM_ID] | $(basename "$0") [--text]    - force output as text"
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

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR::proxmox_node" "STR::vm_name" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

#
# RULES COMING FROM STDIN MUST BE INVERTED ===> cat => tac # TODO
#

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION"

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
