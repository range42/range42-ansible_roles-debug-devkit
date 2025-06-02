#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="vm_start"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

showExample() {
  echo ""
  echo "$(basename "$0") VM_ID"
  echo "$(basename "$0") 4242"
  echo "$(basename "$0") 4200 --json"
  echo "$(basename "$0") 4242 --text"
  echo ""
}

if [ "$1" = '-h' ] ||
  [ "$1" = '--help' ]; then
  echo NAME
  echo "  $(basename "$0") - Start vm_id vm - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo "  $(basename "$0") [-h|--help]"
  echo "  $(basename "$0") [VM_ID] [--json] - force output as json "
  echo "  $(basename "$0") [VM_ID] [--text] - force output as text"
  echo ""
  echo EXAMPLE
  echo "  $(showExample)"
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

ARG_VM_ID="${1:-}"

if [[ -z "$ARG_VM_ID" ]]; then

  devkit_generic.utils.text.echo_error.to.text.to.stderr.sh "no vm_id provided."
  showExample
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

devkit_ansible.proxmox_controller._inc.warmup_checks.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
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
#
# inc lib script call.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ "$OUTPUT_JSON" == true ]]; then
  devkit_ansible.proxmox_controller._inc.basic_vm_actions.to.jsons.sh \
    "$ACTION" "$ARG_VM_ID" --json
else

  devkit_ansible.proxmox_controller._inc.basic_vm_actions.to.jsons.sh \
    "$ACTION" "$ARG_VM_ID" --text
fi
