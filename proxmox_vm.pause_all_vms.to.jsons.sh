#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="vm_pause"
DEFAULT_OUTPUT_JSON=true
ARG_VM_NAME_FILTER=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

showExample() {

  echo "  $(basename "$0") "
  echo "  $(basename "$0") --json "
  echo "  $(basename "$0") vm_name_team_01 --json "
  echo "  $(basename "$0") vm_name_team_02 --json "
  echo "  $(basename "$0") --text "

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then

  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Pause all vm - Execute the specified $ACTION action via Ansible (all vms) "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  $(basename "$0") [--json]                  - force output as json "
  echo "  $(basename "$0") [VM_NAME_FILTER] [--json] - force output as json with filter (grep -i) on vm_name "
  echo "  $(basename "$0") [--text]                  - force output as text"
  echo
  echo EXAMPLE
  echo
  echo "$(showExample)"
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
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

IFS=$'\n'

for VM_ID in $(

  if [[ -n "$ARG_VM_NAME_FILTER" ]]; then
    proxmox_vm.list.to.jsons.sh "$ARG_VM_NAME_FILTER" |
      devkit_transform.jsons.key_field_select.to.jsons.sh 'vm_status' 'running' |
      jq -r '.vm_id'
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
    sleep 3
  fi

done
