#!/bin/bash

#
# PR-51
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="vm_list"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {

  echo "  $(basename "$0") "
  echo "  $(basename "$0") --json"
  echo "  $(basename "$0") --text"
  echo "  $(basename "$0") vm_test_01 --json"
  echo "  $(basename "$0") group_01_vm_01 --json"

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - list VM status - Execute the specified $ACTION action via Ansible - return vm_id as TEXT"
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
  # echo "$(show_example)"
  show_example
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh
proxmox__inc.warmup_checks_stdin.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR::proxmox_node" "STR::action")

#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  JSON_LINE_REQ_TEST=$(jq -r '.vm_id // empty' <<<"$CURRENT_JSON_LINE")

  if [[ -n "$JSON_LINE_REQ_TEST" ]]; then # no associated vm_id ?

    VM_ID_RAW=$(printf '%s\n' "$CURRENT_JSON_LINE" | jq -r ".vm_id")

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox_vm.list.to.jsons.sh |
      devkit_transform.jsons.key_field_int_select.to.jsons.sh "vm_id" "$VM_ID_RAW"

  else
    show_example
  fi

done
