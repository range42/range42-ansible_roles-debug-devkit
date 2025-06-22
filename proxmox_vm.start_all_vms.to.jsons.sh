#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# PR-31
set -euo pipefail

ACTION="vm_start"
DEFAULT_OUTPUT_JSON=true
ARG_VM_NAME_FILTER=""
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {

  echo "  $(basename "$0") "
  echo "  $(basename "$0") --json "
  echo "  $(basename "$0") vm_name_team_01 --json "
  echo "  $(basename "$0") vm_name_team_02 --json "
  echo "  $(basename "$0") --text "
}
if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Start all vm - Execute the specified $ACTION action via Ansible (all vms) "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  $(basename "$0") [--json]                  - force output as json "
  echo "  $(basename "$0") [VM_NAME_FILTER] [--json] - Force output in JSON format with a case insensitive filter on vm_name "
  echo "  $(basename "$0") [--text]                  - force output as text"
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
    show_example
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
    proxmox_vm.list_stopped.to.jsons.sh "$ARG_VM_NAME_FILTER" |
      jq -r '.vm_id'
  else
    proxmox_vm.list_stopped.to.jsons.sh |
      jq -r '.vm_id'
  fi

); do

  ####

  JSON_LINE_REQ=$(printf "%s\n" "$VM_ID" | devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR::proxmox_node" "STR::action")

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$JSON_LINE_REQ" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION"

  else

    printf '%s\n' "$JSON_LINE_REQ" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

    devkit_utils.text.echo_pass.to.text.to.stderr.sh "starting :: $VM_ID"

  fi

  sleep 3

done
