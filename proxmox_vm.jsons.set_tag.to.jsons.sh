#!/bin/bash

#
# ISSUE - 94
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
set -euo pipefail
ACTION="vm_set_tag"
DEFAULT_OUTPUT_JSON=true
# ARG_VM_SNAPSHOT_NAME=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {

  echo
  echo "    echo \"CONFIG_JSON\" | $(basename "$0") --json"
  echo
  echo

  local STDIN_JSON_DATA=(
    '{"vm_id":100, "vm_tag_name": "group_01"} '
    '{"vm_id":100, "vm_tag_name": "group_01,group_02"} '

  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  echo ""

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo
  echo "  $(basename "$0") - set tag/label on VM "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  STDIN :: [JSON] | $(basename "$0")  [--json]  - force output as json *default"
  echo "  STDIN :: [JSON] | $(basename "$0")  [--text]  - force output as text"
  echo ""

  echo EXAMPLE
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

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR::vm_tag_name" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  # CURRENT_JSON_LINE=$NEW_CURRENT_JSON_LINE
  # devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"
  # exit 1

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" #|

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
