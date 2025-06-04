#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="vm_stop"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

showExample() {
  echo
  echo "$(basename "$0") "
  echo
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then

  echo NAME

  echo "  $(basename "$0") - Stop all vm - Execute the specified $ACTION action via Ansible (all vms) "
  echo
  echo SYNOPSIS
  echo "  $(basename "$0") [-h|--help] "
  echo "  $(basename "$0") [VM_ID] [--json] - force output as json "
  echo "  $(basename "$0") [VM_ID] [--text] - force output as text"
  echo ""
  echo EXAMPLE
  echo "  $(showExample)"
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

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
  if [[ -z "$ARG_VM_NAME_FILTER" ]]; then
    ARG_VM_NAME_FILTER="$1"
    shift
  else
    devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
    showExample
    exit 1
  fi
  ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# inc lib script call.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# for VM_ID in $(proxmox_vm.list_running_and_extract_vm_id.to.text.sh); do

#   if [[ "$OUTPUT_JSON" == true ]]; then

#     (
#       echo "$VM_ID" |
#         proxmox__inc.vm_id.basic_vm_actions.to.jsons.sh "$ACTION"
#     )
#   else
#     (
#       echo "$VM_ID" |
#         proxmox__inc.vm_id.basic_vm_actions.to.text.sh "$ACTION"
#     )
#   fi
# for VM_ID in $(devkit_ansible.proxmox_controller

#   devkit_utils.text.echo_pass.to.text.to.stderr.sh "stopping :: $VM_ID"
#   sleep 7 # ACPI shutdown take few seconds...
# done

IFS=$'\n'

for VM_ID in $(

  if [[ -n "$ARG_VM_NAME_FILTER" ]]; then
    proxmox_vm.list_running_and_extract_vm_id.to.text.sh "$ARG_VM_NAME_FILTER" |
      else
    proxmox_vm.list_running_and_extract_vm_id.to.text.sh
  fi

); do

  ####

  if [[ "$OUTPUT_JSON" == true ]]; then
    (
      echo "$VM_ID" |
        proxmox__inc.vm_id.basic_vm_actions.to.jsons.sh "$ACTION"
    )
  else
    (
      echo "$VM_ID" |
        proxmox__inc.vm_id.basic_vm_actions.to.text.sh "$ACTION"
    )

    devkit_utils.text.echo_pass.to.text.to.stderr.sh "stopping :: $VM_ID"
    sleep 7 # ACPI shutdown take few seconds...

  fi

done
