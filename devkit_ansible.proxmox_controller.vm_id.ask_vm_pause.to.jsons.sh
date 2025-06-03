#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="vm_pause"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

showExample() {
  echo
  echo "echo 4242 | $(basename "$0")"
  echo "echo 4242 | $(basename "$0") --json"
  echo "echo 4242 | $(basename "$0") --text"
  echo "cat /tmp/VM_ID | $(basename "$0")"
  echo
  echo "devkit_ansible.proxmox_controller.ask_vm_list.to.jsons.sh group_01 | jq -r '.vm_id' | $(basename "$0")"
  echo "devkit_ansible.proxmox_controller.ask_vm_list.to.jsons.sh group_02 | jq -r '.vm_id' | $(basename "$0")"
  echo
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo NAME
  echo "  $(basename "$0") - Pause vm_id vm - Execute the specified $ACTION action via Ansible "
  echo
  echo SYNOPSIS
  echo "  $(basename "$0") [-h|--help] "
  echo "  stdin|echo|cat| [VM_ID] | $(basename "$0")  [--json] - force output as json *default"
  echo "  stdin|echo|cat| [VM_ID] | $(basename "$0")  [--text] - force output as text"
  echo ""
  echo EXAMPLE
  echo "  $(showExample)"
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

devkit_ansible.proxmox_controller._inc.warmup_checks.sh
devkit_ansible.proxmox_controller._inc.warmup_checks_stdin.sh

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
  devkit_generic.utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
  showExample
  exit 1
  ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# inc lib script call.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

IFS=$'\n'
for VM_ID in $(cat - | tr -d '[:space:]'); do

  if [[ "$OUTPUT_JSON" == true ]]; then
    (
      echo "$VM_ID" |
        devkit_ansible.proxmox_controller._inc.vm_id.basic_vm_actions.to.jsons.sh "$ACTION"
    )
  else
    (
      echo "$VM_ID" |
        devkit_ansible.proxmox_controller._inc.vm_id.basic_vm_actions.to.text.sh "$ACTION"
    )
  fi

done
