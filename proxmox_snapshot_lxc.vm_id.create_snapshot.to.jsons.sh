#!/bin/bash

#
# PR-52
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="snapshot_lxc_create"
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
    '{"proxmox_node":"px-testing", "vm_id":112}'
    '{"proxmox_node":"px-testing", "vm_id":112, "lxc_snapshot_name":"MY_LXC_SNAPSHOT"}'
    '{"proxmox_node":"px-testing", "vm_id":112, "lxc_snapshot_description":"MY_DESCRIPTION" } '
    '{"proxmox_node":"px-testing", "vm_id":112, "lxc_snapshot_name":"MY_LXC_SNAPSHOT", "lxc_snapshot_description":"MY_DESCRIPTION" } '

  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --text"
  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --json"

  echo ""
  echo "    cat /tmp/vm_list.json | $(basename "$0")"
  echo ""
  echo "    proxmox_lxc.list.to.jsons.sh          | jq -r '.vm_id' | $(basename "$0")"
  echo "    proxmox_lxc.list.to.jsons.sh group_02 | jq -r '.vm_id' | $(basename "$0")"
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
  *) ;;
    # if [[ -z "$ARG_VM_SNAPSHOT_NAME" ]]; then
    #   ARG_VM_SNAPSHOT_NAME="$1"
    #   shift
    # else
    #   devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
    #   show_example
    #   exit 1
    # fi
    # ;;
  esac
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR::lxc_snapshot_name" "STR::lxc_snapshot_description" "STR::vm_name" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  IS_VM_SNAPSHOT_NAME=$(jq -r '.lxc_snapshot_name // empty' <<<"$CURRENT_JSON_LINE")
  IS_VM_SNAPSHOT_DESCRIPTION=$(jq -r '.lxc_snapshot_description // empty' <<<"$CURRENT_JSON_LINE")

  ####

  C_ROW=$(printf '%s\n' "$CURRENT_JSON_LINE" |
    proxmox_lxc.list.to.jsons.sh |
    devkit_transform.jsons.key_field_int_select.to.jsons.sh "vm_id" "$(printf '%s\n' "$CURRENT_JSON_LINE" | jq -r '.vm_id // empty')")

  VM_NAME="$(printf '%s\n' "$C_ROW" | jq -r '.lxc_name // empty')"

  ####

  if [[ -z "$IS_VM_SNAPSHOT_NAME" ]]; then               # missing snapshot name ?
    VM_SNAPSHOT_NAME="$VM_NAME-$(date +'%y%m%d-%H%M%S')" # WARNING PROMOX ACCEPT MAX 40 CHARS

  else
    VM_SNAPSHOT_NAME=$(jq -r '.lxc_snapshot_name // empty' <<<"$CURRENT_JSON_LINE")
  fi

  if [[ -z "$IS_VM_SNAPSHOT_DESCRIPTION" ]]; then               # missing snapshot description ?
    VM_SNAPSHOT_DESCRIPTION="$VM_NAME-$(date +'%y%m%d-%H%M%S')" #
  else
    VM_SNAPSHOT_DESCRIPTION=$(jq -r '.lxc_snapshot_description // empty' <<<"$CURRENT_JSON_LINE")
  fi

  NEW_CURRENT_JSON_LINE=$(printf '%s\n' "$CURRENT_JSON_LINE" |
    jq -c \
      --arg jq_lxc_name_v "$VM_NAME" \
      --arg jq_lxc_snapshot_name_v "$VM_SNAPSHOT_NAME" \
      --arg jq_lxc_snapshot_description_v "$VM_SNAPSHOT_DESCRIPTION" \
      '
          . + {
            ("lxc_name"): $jq_lxc_name_v, 
            ("lxc_snapshot_name"): $jq_lxc_snapshot_name_v,
            ("lxc_snapshot_description"): $jq_lxc_snapshot_description_v
            }
        ')

  # JSON HAS BEEN UPDATED MUST BE UPDATED
  CURRENT_JSON_LINE=$NEW_CURRENT_JSON_LINE
  # devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" #|

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
