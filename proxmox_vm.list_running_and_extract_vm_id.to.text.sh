#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="vm_list"

ARG_VM_NAME_FILTER="${1:-}"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

showExample() {
  echo ""
  echo "$(basename "$0") "
  echo "$(basename "$0") --json"
  echo "$(basename "$0") --text"
  echo "$(basename "$0") vm_test_01 --json"
  echo "$(basename "$0") group_01_vm_01 --json"
  echo ""
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then

  echo NAME
  echo "  $(basename "$0") - list VM status - Execute the specified $ACTION action via Ansible - return vm_id as TEXT"
  echo
  echo SYNOPSIS
  echo "  $(basename "$0") [-h|--help]                            - command helper "
  echo "  $(basename "$0") [--json]                               - force output as json "
  echo "  $(basename "$0") [partial_or_complete_vm_name] [--json] - force output as json with filter (grep -i) on vm_name "
  echo "  $(basename "$0") [--text]                               - force output as text"
  echo ""
  echo EXAMPLE
  echo "  $(showExample)"
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# inc lib script call.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ -n "$ARG_VM_NAME_FILTER" ]]; then # check if filter provided in argument

  (
    proxmox_vm.list_running.to.jsons.sh "$ARG_VM_NAME_FILTER" |
      devkit_transform.jsons.key_field_select.to.jsons.sh "vm_status" "running" |
      jq -r '.vm_id'
    #  |
    #   jq -r ' | select (.vm_status=="running") | .vm_id'
  )

else
  (
    proxmox_vm.list_running.to.jsons.sh |
      devkit_transform.jsons.key_field_select.to.jsons.sh "vm_status" "running" |
      jq -r '.vm_id'
  )
fi
