#!/bin/bash

#
# Read the firewall log of one guest. An empty journal is published as ZERO lines plus one
# object carrying vm_fw_log_empty - the api itself answers {n:1, t:"no content"}, which a
# naive reader would count as one entry. And an empty log does not mean nothing was refused :
# logging is off by default - read the log levels with the list_options wrapper next to this.
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_vm_list_log"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"vm_id":100,"proxmox_node":"NODE_NAME"}'
    '{"vm_id":100,"vm_fw_log_limit":"50"}'
    '{"vm_id":100,"vm_fw_log_since":"1757000000","vm_fw_log_until":"1757003600"}'
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
  echo "  $(basename "$0") - Read the firewall log - vm level - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help] "
  echo "  STDIN :: JSON | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: JSON | $(basename "$0") [--text]    - force output as text"
  echo ""
  echo "REQUIRED FIELDS"
  echo
  echo "  vm_id               the guest whose firewall log is read"
  echo "  proxmox_node        the node carrying the guest"
  echo ""
  echo "OPTIONAL FIELDS"
  echo
  echo "  vm_fw_log_limit   max lines returned"
  echo "  vm_fw_log_start   first line index"
  echo "  vm_fw_log_since   unix epoch lower bound"
  echo "  vm_fw_log_until   unix epoch upper bound"
  echo ""
  echo "WHAT AN EMPTY ANSWER DOES AND DOES NOT MEAN"
  echo
  echo "  vm_fw_log_empty says the journal holds no line - it does NOT say nothing was"
  echo "  refused. Logging is off by default : read log_level_in/out with"
  echo "  proxmox_firewall.vm_id.list_options.to.jsons.sh before trusting a silence."
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
  "INT::vm_id" \
  "STR::proxmox_node" \
  "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" |
      jq -c ".[]"

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
