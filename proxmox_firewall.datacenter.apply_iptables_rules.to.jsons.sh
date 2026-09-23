#!/bin/bash

#
# Apply ONE firewall rule on the DATACENTER.
#
# The cluster-level counterpart of the node and guest wrappers, same parameter shape under
# a dc_fw_ prefix. One rule here covers every node, present and future.
#
# TWO FIELDS ARE WORTH PASSING EXPLICITLY
# dc_fw_pos : NOT ACCEPTED ANY MORE. PVE inserts at the TOP of the chain and ignores
#             any position asked for, measured four times the 2026-08-28. Read the chain
#             back with the list action to know where a rule landed. The delete action
#             keeps its position : DELETE by position is the only call the API offers.
# dc_fw_enable : without it the rule is stored DISABLED. It appears in the configuration,
#             it reads as present, and it grants nothing.
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_dc_apply_iptables_rule"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"px-testing\" | $(basename "$0") "
  echo "    echo \"px-testing\" | $(basename "$0") --json"
  echo "    echo \"px-testing\" | $(basename "$0") --text"
  echo
  echo "    cat /tmp/proxmox_node.text | $(basename "$0")"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    \
    '{"proxmox_node":"px-testing","dc_fw_action":"ACCEPT","dc_fw_type":"in","dc_fw_proto":"tcp","dc_fw_dport":"22","dc_fw_enable":1}'
    '{"proxmox_node":"px-testing","dc_fw_action":"DROP","dc_fw_type":"in","dc_fw_enable":1}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[0]}")" "$(basename "$0") --json"

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Apply iptables rules - datacenter firewall - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                            $(basename "$0") [-h|--help] "
  echo "  STDIN :: [proxmox_node] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [proxmox_node] | $(basename "$0") [--text]    - force output as text"
  echo ""
  echo OPTIONAL FIELDS
  echo
  echo "  dc_fw_pos       NOT ACCEPTED. PVE inserts at the top and ignores it."
  echo "  dc_fw_enable    1 to make it active. WITHOUT IT THE RULE IS STORED DISABLED."
  echo "  dc_fw_iface     dc_fw_source  dc_fw_dest  dc_fw_proto  dc_fw_dport  dc_fw_sport"
  echo "  dc_fw_log       dc_fw_comment"
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

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh \
  "STR::proxmox_node" \
  "STR::dc_fw_action" \
  "STR::dc_fw_type" \
  "STR::dc_fw_iface" \
  "STR::dc_fw_source" \
  "STR::dc_fw_dest" \
  "STR::dc_fw_proto" \
  "STR::dc_fw_dport" \
  "STR::dc_fw_sport" \
  "STR::dc_fw_enable" \
  "STR::dc_fw_comment" \
  "STR::dc_fw_log" \
  "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  if [[ "$OUTPUT_JSON" == true ]]; then

    # devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"
    # exit 0

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION"

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
