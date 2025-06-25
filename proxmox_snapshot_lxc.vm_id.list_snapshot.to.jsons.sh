#!/bin/bash

#
# PR-54
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# PR-29
set -euo pipefail
ACTION="snapshot_lxc_list"
DEFAULT_OUTPUT_JSON=true
ARG_LXC_SNAPSHOT_NAME=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"100\" | $(basename "$0") "
  echo "    echo \"101\" | $(basename "$0") --json"
  echo "    echo \"102\" | $(basename "$0") --text"
  echo
  echo "    cat /tmp/proxmox_nodes.text | $(basename "$0")"
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

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") lxc_snapshot_name --json"

  echo ""
  echo "    cat /tmp/proxmox_nodes.json | $(basename "$0")"
  echo
  echo "    proxmox_vm.list.to.jsons.sh          | jq -r '.vm_id' | $(basename "$0")"
  echo "    proxmox_vm.list.to.jsons.sh group_02 | jq -r '.vm_id' | $(basename "$0")"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - List LXC snapshot - require : vm_id vm - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                     $(basename "$0") [-h|--help] "
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [--json]                                     - force output as json *default"
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [--text]                                     - force output as text"
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [partial_or_complete_snapshot_name] [--json] - Force output in JSON format with a case insensitive filter on vm_snapshot_name "
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
    if [[ -z "$ARG_LXC_SNAPSHOT_NAME" ]]; then
      ARG_LXC_SNAPSHOT_NAME="$1"
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

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR::lxc_name" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r VM_ID; do

  if [[ "$OUTPUT_JSON" == true ]]; then

    if [[ -n "$ARG_LXC_SNAPSHOT_NAME" ]]; then # check if filter provided in argument

      printf '%s\n' "$VM_ID" |
        proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" |
        jq -c '.[]' |
        devkit_transform.jsons.key_field_greper.to.jsons.sh "lxc_snapshot_name" "$ARG_LXC_SNAPSHOT_NAME"

    else

      printf '%s\n' "$VM_ID" |
        proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" |
        jq -c '.[]'

    fi

  else

    printf '%s\n' "$VM_ID" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
