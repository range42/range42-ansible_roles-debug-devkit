#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="snapshot_lxc_list"
DEFAULT_OUTPUT_JSON=true

ARG_LXC_SNAPSHOT_NAME=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

showExample() {

  echo "echo 100 | $(basename "$0")"
  echo "echo 100 | $(basename "$0") --json"
  echo "echo 100 | $(basename "$0") --text"
  echo "cat /tmp/VM_ID | $(basename "$0")"
  echo
  echo "echo 100 | $(basename "$0") snapshot_name --json"
  echo
  echo "proxmox_vm.list.to.jsons.sh group_01 | jq -r '.vm_id' | $(basename "$0")"
  echo "proxmox_vm.list.to.jsons.sh group_02 | jq -r '.vm_id' | $(basename "$0")"

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - List LXC snapshot - require : vm_id vm - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                     $(basename "$0") [-h|--help] "
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [--json]                                     - force output as json *default"
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [partial_or_complete_snapshot_name] [--json] - force output as json with filter (grep -i) on lxc_snapshot_name "
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [--text]                                     - force output as text"
  echo
  echo EXAMPLE
  echo
  echo "$(showExample)"
  echo
  echo
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

while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    OUTPUT_JSON=true
    shift
    ;;
  --text)
    OUTPUT_JSON=false
    shift
    ;;
  -*)
    devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
    showExample
    exit 1
    ;;
  *)
    if [[ -z "$ARG_LXC_SNAPSHOT_NAME" ]]; then
      ARG_LXC_SNAPSHOT_NAME="$1"
      shift
    else
      devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
      showExample
      exit 1
    fi
    ;;
  esac
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# inc lib script call.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

IFS=$'\n'
for VM_ID in $(cat - ); do

  if [[ "$OUTPUT_JSON" == true ]]; then

    if [[ -n "$ARG_LXC_SNAPSHOT_NAME" ]]; then # check if filter provided in argument
      (
        echo "$VM_ID" |
          proxmox__inc.vm_id.basic_vm_actions.to.jsons.sh "$ACTION" |
          jq -c '.[]' |
          devkit_transform.jsons.key_field_greper.to.jsons.sh "lxc_snapshot_name" "$ARG_LXC_SNAPSHOT_NAME"
      )

    else
      (
        echo "$VM_ID" |
          proxmox__inc.vm_id.basic_vm_actions.to.jsons.sh "$ACTION" |
          jq -c '.[]'
      )
    fi

  else
    (
      echo "$VM_ID" |
        proxmox__inc.vm_id.basic_vm_actions.to.text.sh "$ACTION" |
        jq -c '.[]'
    )
  fi

done
