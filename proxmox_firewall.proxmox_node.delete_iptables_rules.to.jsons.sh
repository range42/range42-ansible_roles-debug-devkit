#!/bin/bash

#
# Delete ONE firewall rule of one NODE, by position.
#
# >>> THE POSITION IS A MOVING TARGET <<<
# Proxmox renumbers the chain after every deletion, and inserting a rule shifts everything
# below it. A position read earlier is therefore stale by the time it is used. Measured at
# guest level : deleting position 0 of a two-rule chain renumbered the survivor from 1 to 0.
# Read the chain immediately before deleting, or delete from the highest position downwards.
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_node_delete_iptables_rule"
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
    '{"proxmox_node":"px-testing","node_fw_pos":0}'
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
  echo "  $(basename "$0") - Delete specified iptables rule - node firewall - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                            $(basename "$0") [-h|--help] "
  echo "  STDIN :: [proxmox_node] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [proxmox_node] | $(basename "$0") [--text]    - force output as text"
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
  "STR::node_fw_pos" \
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
