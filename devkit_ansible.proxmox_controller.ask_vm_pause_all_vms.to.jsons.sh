#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="vm_pause"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

showExample() {
  echo ""
  echo "$(basename "$0") "

  echo ""
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then

  echo NAME

  echo "  $(basename "$0") - Pause all vm - Execute the specified $ACTION action via Ansible (all vms) "
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

devkit_ansible.proxmox_controller._inc.warmup_checks.sh

### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# define output type
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

case "${2:-}" in
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
#I
# inc lib script call.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

for VM_ID in $(devkit_ansible.proxmox_controller.ask_vm_list_running_and_extract_vm_id.to.text.sh); do

  if [[ "$OUTPUT_JSON" == true ]]; then

    (
      echo "$VM_ID" | devkit_ansible.proxmox_controller._inc.vm_id.basic_vm_actions.to.jsons.sh \
        "$ACTION" --json
    )

  else

    (
      echo "$VM_ID" | devkit_ansible.proxmox_controller._inc.vm_id.basic_vm_actions.to.jsons.sh \
        "$ACTION" --text
    )
    devkit_generic.utils.text.echo_pass.to.text.to.stderr.sh "stopping :: $VM_ID "
    sleep 3 #
  fi
done
