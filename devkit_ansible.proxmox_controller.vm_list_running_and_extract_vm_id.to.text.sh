#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="vm_list"
DEFAULT_OUTPUT_JSON=true

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

devkit_ansible.proxmox_controller._inc.warmup_checks.sh

# #
# # check if role can be found in ANSIBLE_ROLES_PATH
# #

# if [[ -z "${ANSIBLE_ROLES_PATH:-}" ]]; then
#   echo ":: ENV_ERROR ::  ANSIBLE_ROLES_PATH not defined"
#   exit 1
# fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# check output type.

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
  echo ":: ERROR :: invalid argument.  '$2'." >&2

  ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# inc lib script call.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ "$OUTPUT_JSON" == true ]]; then

  if [[ -n "$ARG_VM_NAME_FILTER" ]]; then # check if filter provided in argument

    (
      # devkit_ansible.proxmox_controller._inc.basic_vm_actions_no_args.to.jsons.sh \
      #   "$ACTION" --json |
      #   devkit_generic.tr.jsons.remove_key.to.jsons.sh "vm_meta" |

      devkit_ansible.proxmox_controller.vm_list_running.to.jsons "$ARG_VM_NAME_FILTER" |
        jq -r '. | select (.vm_status=="running") | .vm_id'
    )

  else
    (

      devkit_ansible.proxmox_controller.vm_list_running.to.jsons |
        jq -r '. | select (.vm_status=="running") | .vm_id'

      # devkit_ansible.proxmox_controller._inc.basic_vm_actions_no_args.to.jsons.sh \
      #   "$ACTION" --json |
      #   devkit_generic.tr.jsons.remove_key.to.jsons.sh "vm_meta" |
      #   jq -r '. | select (.vm_status=="running") | .vm_id'
    )
  fi
else

  (
    devkit_ansible.proxmox_controller._inc.basic_vm_actions_no_args.to.jsons.sh \
      "$ACTION" --text
  )
fi
