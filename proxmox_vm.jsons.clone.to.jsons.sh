#!/bin/bash

#
# ISSUE - 93
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
set -euo pipefail
ACTION="vm_clone"
DEFAULT_OUTPUT_JSON=true
# ARG_VM_SNAPSHOT_NAME=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {

  echo
  echo "    echo \"CONFIG_JSON\" | $(basename "$0") --json"
  echo
  echo

  local STDIN_JSON_DATA=(
    '{"vm_id":100, "vm_new_id": 1001} '
    '{"vm_id":100, "vm_new_id": 1001, "vm_name":"test-cloned"} '
    '{"vm_id":100, "vm_new_id": 1001, "vm_name":"test-cloned", "vm_description":"my description"}'

  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  echo ""

  ## TESTING :
  # echo 1001 | proxmox_vm.vm_id.delete.to.jsons.sh ;  echo '{"vm_id":100,"vm_new_id":1001,"vm_name":"test-bbbb"}'   | proxmox_vm.jsons.clone.to.jsons.sh
  # echo 1001 | proxmox_vm.vm_id.delete.to.jsons.sh ;  echo '{"vm_id":100,"vm_new_id":1001,"vm_name":"test-bbbb", "vm_decription": "something"}'   | proxmox_vm.jsons.clone.to.jsons.sh

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo
  echo "  $(basename "$0") - clone LXC - require CONFIG_JSON - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  STDIN :: [JSON] | $(basename "$0")  [--json]       - force output as json *default"
  echo "  STDIN :: [JSON] | $(basename "$0")  [--text]       - force output as text"
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

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "INT::vm_new_id" "STR::vm_name" "STR::vm_description" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  VM_NAME=$(jq -r '.vm_name // empty' <<<"$CURRENT_JSON_LINE")
  VM_SNAPSHOT_DESCRIPTION=$(jq -r '.vm_description // empty' <<<"$CURRENT_JSON_LINE")

  if [[ -z "$VM_NAME" ]]; then # missing vm_°name ?

    OLD_VM_NAME=$(printf "%s\n" "$JSON_LINE_REQ" | proxmox_vm.vm_id.list_vm_and_extract_vm_name.to.jsons.sh | jq -r ".vm_name")
    VM_NAME="$OLD_VM_NAME-cloned"
  fi

  if [[ -z "$VM_SNAPSHOT_DESCRIPTION" ]]; then # missing snapshot description ?

    OLD_VM_NAME=$(printf "%s\n" "$JSON_LINE_REQ" | proxmox_vm.vm_id.list_vm_and_extract_vm_name.to.jsons.sh | jq -r ".vm_name")
    VM_SNAPSHOT_DESCRIPTION="FULL clone from $OLD_VM_NAME"
  # else

  #   VM_SNAPSHOT_DESCRIPTION=$(jq -r '.vm_description // empty' <<<"$CURRENT_JSON_LINE")
  fi

  NEW_CURRENT_JSON_LINE=$(printf '%s\n' "$CURRENT_JSON_LINE" |
    jq -c \
      --arg jq_vm_description_v "$VM_SNAPSHOT_DESCRIPTION" \
      --arg jq_vm_name_v "$VM_NAME" \
      ' . + {
     ("vm_description"): $jq_vm_description_v  ,
     ("vm_name"): $jq_vm_name_v  
     }')

  #
  # update current json line with changes
  #
  CURRENT_JSON_LINE=$NEW_CURRENT_JSON_LINE
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
