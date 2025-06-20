#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="snapshot_lxc_create"
DEFAULT_OUTPUT_JSON=true
ARG_VM_SNAPSHOT_NAME=""

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
    '{"proxmox_node":"px-testing", "vm_id":100, "vm_snapshot_name":"MY_SNAPSHOT"}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") vm_snapshot_name --json"

  echo ""
  echo "    cat /tmp/vm_list.json | $(basename "$0")"
  echo ""
  echo "    proxmox_vm.list.to.jsons.sh          | jq -r '.vm_id' | $(basename "$0")"
  echo "    proxmox_vm.list.to.jsons.sh group_02 | jq -r '.vm_id' | $(basename "$0")"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo
  echo "  $(basename "$0") - create LXC snapshot - require vm_id  - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [--json]                                     - force output as json *default"
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [partial_or_complete_snapshot_name] [--json] - Force output in JSON format with a case insensitive filter on vm_snapshot_name "
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [--text]                                     - force output as text"
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
  *)
    if [[ -z "$ARG_VM_SNAPSHOT_NAME" ]]; then
      ARG_VM_SNAPSHOT_NAME="$1"
      shift
    else
      devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
      show_example
      exit 1
    fi
    ;;
  esac
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR::vm_snapshot_name" "STR::vm_name" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  # devkit_utils.text.echo_trace.to.text.to.stderr.sh "$VM_ID"

  JSON_LINE_REQ_TEST=$(jq -r '.vm_snapshot_name // empty' <<<"$CURRENT_JSON_LINE")

  if [[ -z "$JSON_LINE_REQ_TEST" ]]; then # missing snapshot name ?

    C_ROW=$(printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox_vm.list.to.jsons.sh |
      devkit_transform.jsons.key_field_int_select.to.jsons.sh "vm_id" "$(printf '%s\n' "$CURRENT_JSON_LINE" | jq -r '.vm_id // empty')")

    VM_NAME="$(printf '%s\n' "$C_ROW" | jq -r '.vm_name // empty')"
    VM_SNAPSHOT_NAME="$VM_NAME-$(date +'%y%m%d-%H%M%S')" # WARNING PROMOX ACCEPT MAX 40 CHARS

    NEW_CURRENT_JSON_LINE=$(printf '%s\n' "$CURRENT_JSON_LINE" |
      jq -c \
        --arg jq_lxc_name_v "$VM_NAME" \
        --arg jq_lxc_snapshot_name_v "$VM_SNAPSHOT_NAME" \
        '
          . + {
            ("vm_name"): $jq_lxc_name_v, 
            ("vm_snapshot_name"): $jq_lxc_snapshot_name_v
            }
        ')

    # JSON HAS BEEN UPDATED MUST BE UPDATED

    CURRENT_JSON_LINE=$NEW_CURRENT_JSON_LINE

  fi

  devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" #|

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
