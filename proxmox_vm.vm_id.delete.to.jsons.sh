#!/bin/bash

#
# PR-67
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="vm_delete"
# DEFAULT_OUTPUT_JSON=true # TODO
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

  local STDIN_JSON_DATA=(
    '{"vm_id":100}'
    '{"proxmox_node":"px-testing", "vm_id":100}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") vm_name_or_group --json"

  echo ""
  echo "    cat /tmp/vm_list.json | $(basename "$0")"
  echo
  echo "    proxmox_vm.list.to.jsons.sh          | jq -r '.vm_id' | $(basename "$0")"
  echo "    proxmox_vm.list.to.jsons.sh group_02 | jq -r '.vm_id' | $(basename "$0")"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo "  $(basename "$0") - delete VM - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                     $(basename "$0") [-h|--help] "
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [--json] - force output as json *default"
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [--text] - force output as text"
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

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR:vm_name" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  # enrich json with vm_name
  VM_NAME=$(
    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox_vm.vm_id.list_vm_and_extract_vm_name.to.jsons.sh |
      jq -r '.vm_name // empty'
  )

  # merge jsons

  NEW_CURRENT_JSON_LINE=$(
    printf '%s\n' "$CURRENT_JSON_LINE" |
      jq -c --arg jq_vm_name_v "$VM_NAME" '. + { ("vm_name"): $jq_vm_name_v }'
  )

  # update current json line
  CURRENT_JSON_LINE=$NEW_CURRENT_JSON_LINE

  devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"
  # exit 0

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION"

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
