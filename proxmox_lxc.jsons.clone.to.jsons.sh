#!/bin/bash

#
# ISSUE - 86
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
set -euo pipefail
ACTION="lxc_clone"
DEFAULT_OUTPUT_JSON=true
# ARG_VM_SNAPSHOT_NAME=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {

  echo
  echo "    echo \"CONFIG_JSON\" | $(basename "$0") --json"
  echo
  echo

  local STDIN_JSON_DATA=(
    '{"vm_id":801, "vm_new_id": 802} '
    '{"vm_id":801, "vm_new_id": 802, "lxc_name":"test-cloned"} '
    '{"vm_id":801, "vm_new_id": 802, "lxc_name":"test-cloned", "lxc_description":"my description"}'

  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  echo ""

  ## TESTING :
  # echo 802 | proxmox_lxc.vm_id.delete.to.jsons.sh ;  echo '{"vm_id":801,"vm_new_id":802,"lxc_name":"test-bbbb"}'   | proxmox_lxc.jsons.clone.to.jsons.sh --text
  # echo 802 | proxmox_lxc.vm_id.delete.to.jsons.sh ;  echo '{"vm_id":801,"vm_new_id":802,"lxc_name":"test-bbbb", "lxc_decription": "something"}'   | proxmox_lxc.jsons.clone.to.jsons.sh --text

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

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "INT::vm_new_id" "STR::lxc_name" "STR::lxc_description" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  LXC_NAME=$(jq -r '.lxc_name // empty' <<<"$CURRENT_JSON_LINE")
  LXC_SNAPSHOT_DESCRIPTION=$(jq -r '.lxc_description // empty' <<<"$CURRENT_JSON_LINE")

  if [[ -z "$LXC_NAME" ]]; then # missing vm_°name ?

    OLD_LXC_NAME=$(printf "%s\n" "$JSON_LINE_REQ" | proxmox_lxc.vm_id.list_lxc_and_extract_vm_name.to.jsons.sh | jq -r ".lxc_name")
    LXC_NAME="$OLD_LXC_NAME-cloned"
  fi

  if [[ -z "$LXC_SNAPSHOT_DESCRIPTION" ]]; then # missing snapshot description ?

    OLD_LXC_NAME=$(printf "%s\n" "$JSON_LINE_REQ" | proxmox_lxc.vm_id.list_lxc_and_extract_vm_name.to.jsons.sh | jq -r ".lxc_name")
    LXC_SNAPSHOT_DESCRIPTION="FULL clone from $OLD_LXC_NAME"
  else

    LXC_SNAPSHOT_DESCRIPTION=$(jq -r '.lxc_description // empty' <<<"$CURRENT_JSON_LINE")
  fi

  NEW_CURRENT_JSON_LINE=$(printf '%s\n' "$CURRENT_JSON_LINE" |
    jq -c \
      --arg jq_lxc_description_v "$LXC_SNAPSHOT_DESCRIPTION" \
      --arg jq_lxc_name_v "$LXC_NAME" \
      ' . + { 
     ("lxc_description"): $jq_lxc_description_v ,
     ("lxc_name"): $jq_lxc_name_v 
      }')

  # update current json line with changes
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
