#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="vm_stop"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

showExample() {
  echo
  echo "echo 4242 | $(basename "$0")"
  echo "echo 4242 | $(basename "$0") --json"
  echo "echo 4242 | $(basename "$0") --text"
  echo "cat /tmp/VM_ID | $(basename "$0")"
  echo
  echo "proxmox_vm.list.to.jsons.sh group_01 | jq -r '.vm_id' | $(basename "$0")"
  echo "proxmox_vm.list.to.jsons.sh group_02 | jq -r '.vm_id' | $(basename "$0")"
  echo
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo NAME
  echo "  $(basename "$0") - Stop (acpi) vm_id vm - Execute the specified $ACTION action via Ansible "
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
proxmox__inc.warmup_checks_stdin.sh

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
  devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
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
        proxmox__inc.vm_id.basic_vm_actions.to.jsons.sh "$ACTION"
    )
  else
    (

      echo "$VM_ID" |
        proxmox__inc.vm_id.basic_vm_actions.to.text.sh "$ACTION"
    )
  fi
done
