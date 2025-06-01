#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="vm_list"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

showExample() {
  echo ""
  echo "$(basename "$0") VM_ID"
  echo "$(basename "$0") 24242"
  echo "$(basename "$0") 34242"
  echo ""
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then

  echo NAME
  echo "  $(basename "$0") - list VM status - Execute the specified $ACTION action via Ansible "
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

#
# check if role can be found in ANSIBLE_ROLES_PATH
#

if [[ -z "${ANSIBLE_ROLES_PATH:-}" ]]; then
  echo ":: ENV_ERROR ::  ANSIBLE_ROLES_PATH not defined"
  exit 1
fi

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

# TODO :  add arg for host.
# #
# (
#   devkit_ansible.proxmox_controller._inc.basic_vm_actions_no_args.to.jsons.sh "$ACTION" |
#     jq \
#       --arg jqa_ACTION "$ACTION" \
#       '
#       .plays[].tasks[]
#         | .hosts[]
#         | select(type == "object" and has($jqa_ACTION))
#         | .vm_list[]
#         ' |
#     jq '
#       {
#           vm_name:    (.name                 // "?"),
#           vm_status:  (.status               // "?"),
#           vm_id:      (.vmid                 // "?"),
#           vm_uptime:  (.uptime               // "?"),
#           vm_meta: {
#             cpu_current_usage:   (.cpu       // "?"),
#             cpu_allocated:       (.cpus      // "?"),
#             disk_current_usage:  (.disk      // "?"),
#             disk_read:           (.diskread  // "?"),
#             disk_write:          (.diskwrite // "?"),
#             disk_max:            (.maxdisk   // "?"),
#             ram_current_usage:   (.mem       // "?"),
#             ram_max:             (.maxmem    // "?"),
#             net_in:              (.netin     // "?"),
#             net_out:             (.netout    // "?")
#           }
#       }' |
#     devkit_generic.tr.jsons.remove_key.to.jsons.sh "vm_meta"
# )

if [[ "$OUTPUT_JSON" == true ]]; then
  (
    devkit_ansible.proxmox_controller._inc.basic_vm_actions_no_args.to.jsons.sh \
      "$ACTION" --json |
      jq --arg action "$ACTION" '
        .plays[].tasks[] 
        | .hosts[] 
        | select(type=="object" and has($action)) 
        | .[$action]
      ' | jq ".[]" | devkit_generic.tr.jsons.remove_key.to.jsons.sh "vm_meta"
  )
else

  (
    devkit_ansible.proxmox_controller._inc.basic_vm_actions_no_args.to.jsons.sh \
      "$ACTION" --text
  )
fi
