#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_dc_add_iptables_alias"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"proxmox_node":"NODE_NAME","dc_fw_alias_name":"ALIAS_NAME","dc_fw_alias_cidr":"CIDR"}'
    '{"proxmox_node":"NODE_NAME","dc_fw_alias_name":"ALIAS_NAME","dc_fw_alias_cidr":"CIDR","dc_fw_alias_comment":"COMMENT"}'
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
  echo "  $(basename "$0") - Add an iptables alias - datacenter firewall - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help] "
  echo "  STDIN :: JSON | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: JSON | $(basename "$0") [--text]    - force output as text"
  echo ""
  echo "REQUIRED FIELDS"
  echo
  echo "  proxmox_node        the node the api call is made against"
  echo "  dc_fw_alias_name    the name the rules will refer to"
  echo "  dc_fw_alias_cidr    the address or network the name stands for"
  echo ""
  echo "OPTIONAL FIELDS"
  echo
  echo "  dc_fw_alias_comment free text stored beside the alias"
  echo ""
  echo "  WHERE ALIASES LIVE"
  echo "  "
  echo "    Aliases are a cluster-wide and a per-guest object. The api exposes them under"
  echo "    the datacenter and under a guest, and nowhere under a node. A datacenter alias"
  echo "    is already visible from the rules of every node, so there is nothing a"
  echo "    node-level alias could scope."
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

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh \
  "STR::proxmox_node" \
  "STR::dc_fw_alias_name" \
  "STR::dc_fw_alias_cidr" \
  "STR::dc_fw_alias_comment" \
  "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION"

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
