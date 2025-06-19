#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="vm_list"
DEFAULT_OUTPUT_JSON=true
ARG_VM_NAME_FILTER=""
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# show_example() {

#   echo "  $(basename "$0") "
#   echo "  $(basename "$0") "
#   echo "  $(basename "$0") --json"
#   echo "  $(basename "$0") --text"
#   echo "  $(basename "$0") vm_test_01 --json"
#   echo "  $(basename "$0") group_01_vm_01 --json"

# }

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    $(basename "$0") "
  echo "    $(basename "$0") --json"
  echo "    echo \"px-node-02\" | $(basename "$0") --text"
  echo
  echo "    cat /tmp/proxmox_nodes.text | $(basename "$0")"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"proxmox_node":"px-testing"}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") vm_test_01 --json"
  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") group_01 --json"

  echo ""
  echo "    cat /tmp/proxmox_nodes.json | $(basename "$0")"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then

  echo
  echo NAME
  echo
  echo "  $(basename "$0") - list VM status - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help]                            - command helper "
  echo "  $(basename "$0") [--json]                               - force output as json "
  echo "  $(basename "$0") [partial_or_complete_vm_name] [--json] - Force output in JSON format with a case insensitive filter on vm_name "
  echo "  $(basename "$0") [--text]                               - force output as text"
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

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# check output type.
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
  if [[ -z "$ARG_VM_NAME_FILTER" ]]; then
    ARG_VM_NAME_FILTER="$1"
    shift
  else
    devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
    show_example
    exit 1
  fi

  ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r PX_NODE; do

  if [[ "$OUTPUT_JSON" == true ]]; then
    if [[ -n "$ARG_VM_NAME_FILTER" ]]; then # check if filter provided in argument

      printf '%s\n' "$PX_NODE" |
        proxmox_vm.list.to.jsons.sh "$ARG_VM_NAME_FILTER" |
        devkit_transform.jsons.key_field_select.to.jsons.sh 'vm_status' 'running' # investigate bug.
      # devkit_transform.jsons.key_field_select.to.jsons.sh 'vm_status' 'paused'

    else

      printf '%s\n' "$PX_NODE" |
        proxmox_vm.list.to.jsons.sh "$ARG_VM_NAME_FILTER" |
        devkit_transform.jsons.key_field_select.to.jsons.sh 'vm_status' 'running' # investigate bug.
      # devkit_transform.jsons.key_field_select.to.jsons.sh 'vm_status' 'paused'

    fi

  else

    printf '%s\n' "$PX_NODE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
