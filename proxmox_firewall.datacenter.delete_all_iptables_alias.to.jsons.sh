#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_dc_delete_iptables_alias"
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
  echo "  $(basename "$0") - Delete ALL iptables aliases - datacenter firewall - Execute the specified $ACTION action via Ansible "
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
  echo ""
  echo "OPTIONAL FIELDS"
  echo
  echo "  none : this composite reads the alias list itself"
  echo ""
  echo "  WHAT THIS DOES NOT DO"
  echo "  "
  echo "    It removes every alias defined at the datacenter level. Rules that referred to"
  echo "    them are left behind, pointing at names that no longer resolve. Nothing here"
  echo "    refuses, so list the aliases and the chain first."
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
# An alias is addressed by NAME, not by rank, so this composite needs no ordering care : a
# name does not move when a neighbour disappears. The rule equivalent does need it, and says
# so in its own header.
#

JSON_LINE_REQ=$(
  devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::proxmox_node" "STR::action" |
    proxmox_firewall.datacenter.list_iptables_alias.to.jsons.sh
)

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [ -z "${JSON_LINE_REQ//[[:space:]]/}" ]; then
  devkit_utils.text.echo_error.to.text.to.stderr.sh "no alias is defined at this level : nothing to delete."
  exit 0
fi

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  [ -n "${CURRENT_JSON_LINE//[[:space:]]/}" ] || continue

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$CURRENT_JSON_LINE" |
      jq -c '{ proxmox_node, dc_fw_alias_name }' |
      proxmox_firewall.datacenter.delete_iptables_alias.to.jsons.sh --json

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      jq -c '{ proxmox_node, dc_fw_alias_name }' |
      proxmox_firewall.datacenter.delete_iptables_alias.to.jsons.sh --text

  fi

done
