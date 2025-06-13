#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="vm_list"
DEFAULT_OUTPUT_JSON=true
ARG_VM_NAME_FILTER=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

showExample() {

  echo "  $(basename "$0") "
  echo "  $(basename "$0") --json"
  echo "  $(basename "$0") --text"
  echo "  $(basename "$0") test_vm_01 --json"
  echo "  $(basename "$0") group_01_vm_01 --json"

}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo
  echo
  echo NAME
  echo "  $(basename "$0") - list VM status - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTION
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  $(basename "$0") [--json]                               - force output as json "
  echo "  $(basename "$0") [partial_or_complete_vm_name] [--json] - force output as json with filter (grep -i) on vm_name "
  echo "  $(basename "$0") [--text]                               - force output as text (debug purpose)"
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

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# browse provided arugments :
# - look for output types or filter on vm_name
#

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
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# inc lib script call.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ "$OUTPUT_JSON" == true ]]; then # json mode.

  if [[ -n "$ARG_VM_NAME_FILTER" ]]; then # check if filter provided in argument

    (
      proxmox__inc.basic_vm_actions.to.jsons.sh "$ACTION" |
        jq '.[]' |
        devkit_transform.jsons.remove_key.to.jsons.sh "vm_meta" |
        devkit_transform.jsons.key_field_greper.to.jsons.sh "vm_name" "$ARG_VM_NAME_FILTER"
    )

  else # not filter in argument

    (
      proxmox__inc.basic_vm_actions.to.jsons.sh "$ACTION" |
        jq '.[]' |
        devkit_transform.jsons.remove_key.to.jsons.sh "vm_meta"
    )

  fi
else # text output mode  - debug

  (
    proxmox__inc.basic_vm_actions.to.text.sh "$ACTION"
  )

fi
