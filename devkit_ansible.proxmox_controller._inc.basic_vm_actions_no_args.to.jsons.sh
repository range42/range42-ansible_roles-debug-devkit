#!/bin/bash

if [ "$1" = '-h' ] ||
  [ "$1" = '--help' ]; then
  echo NAME
  echo "  $(basename "$0") - LIB / INCLUDE script providing basic generic helper func for start|stop|pause|ect proxmox"
  echo
  echo SYNOPSIS
  echo "  $(basename "$0") [-h|--help] [URL]"
  echo "  $(basename "$0") [ACTION] [--json] - force output as json "
  echo "  $(basename "$0") [ACTION] [--text] - force output as text"
  echo ""
  echo EXAMPLE
  echo "  $(showExample)"
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ROLE_NAME="range42-ansible_roles-proxmox_controller"
DEFAULT_OUTPUT_JSON=true
DEFAULT_OPEN_VAULT_PW_FILE_PATH="/tmp/vault/vault_pass.txt"

ARG_ACTION="${1:-}"
# ARG_VM_ID="${2:-}"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# check if arguments provided
if [[ -z "$ARG_ACTION" ]]; then
  showExample
  exit 1
fi

# quick dirty notes :

# vm_create - multiple

# firewall_dc_enable - 0
# firewall_node_enable - 0
# firewall_vm_enable - ok

# snapshot_create - ok - 2
# snapshot_delete - ok - 2
# snapshot_rollback - arg 2 ?

# vm_delete - ok
# vm_pause - ok
# vm_resume - ok
# vm_start - ok
# vm_stop - ok
# vm_stop_force - ok

# white listing doc helper
case "$ARG_ACTION" in
vm_delete | vm_pause | vm_resume | vm_start | vm_stop | vm_stop_force | vm_list) ;;
*)
  echo ""
  echo ":: ERROR   :: invalid action: $ARG_ACTION"
  echo ":: ALLOWED :: start | stop | pause | reset | resume"
  echo ""
  exit 1
  ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

devkit_ansible.proxmox_controller._inc.warmup_checks.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# # check if role can be found in ANSIBLE_ROLES_PATH
# if [[ -z "${ANSIBLE_ROLES_PATH:-}" ]]; then
#   echo ""
#   echo ":: ENV_ERROR :: ANSIBLE_ROLES_PATH not defined"
#   echo ""
#   exit 1
# fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# check output type.

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

case "${3:-}" in
--json)
  OUTPUT_JSON=true
  ;;
--text)
  OUTPUT_JSON=false
  ;;

"") ;;
*)

  devkit_generic.utils.text.echo_error.to.text.to.stderr.sh "invalid arguments '$2'"

  ;;

esac

if [[ "$OUTPUT_JSON" == true ]]; then
  CURRENT_ANSIBLE_CONFIG="./ansible_no_skipped_json.cfg"
else
  # CURRENT_ANSIBLE_CONFIG="./ansible_no_skipped.cfg"
  CURRENT_ANSIBLE_CONFIG="./ansible.cfg"
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# open vault - look for ansible-agent
#

if [[ -f $DEFAULT_OPEN_VAULT_PW_FILE_PATH ]]; then
  ANSIBLE_VAULT_ARG=(--vault-password-file "$DEFAULT_OPEN_VAULT_PW_FILE_PATH")

else

  OPEN_VAULT_PW_FILE_PATH=$(devkit_ansible.open_vault.to.file.sh)
  ANSIBLE_VAULT_ARG=(--vault-password-file "$OPEN_VAULT_PW_FILE_PATH")

fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# inline playbook execution
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

(
  # ANSIBLE_STDOUT_CALLBACK=json \ # we can still use json as call back but the next call back should reduce the volume of data in returned json from ansible.
  # ANSIBLE_STDOUT_CALLBACK=no_skipped \

  # ANSIBLE_CONFIG="./ansible_no_skipped_json.cfg" \
  ANSIBLE_CONFIG="$CURRENT_ANSIBLE_CONFIG" \
    ansible-playbook -i "$RANGE42_ANSIBLE_ROLES__INVENTORY_DIR/off_cr_42.yaml" \
    "${ANSIBLE_VAULT_ARG[@]}" \
    /dev/stdin <<EOF

- hosts: px-testing
  gather_facts: false
  vars_files:
    - "$RANGE42_ANSIBLE_ROLES__DEVKITS_DIR/secrets/px-testing.cr42_tailscale.yaml"
  tasks:
    - name: RUN $ROLE_NAME WITH VARS
      include_role:
        name: $ROLE_NAME
      vars:
        proxmox_vm_action: "$ARG_ACTION"
        
      
EOF
) | jq --arg action "$ARG_ACTION" '
        .plays[].tasks[]
        | .hosts[]
        | select(type=="object" and has($action))
        | .[$action]
      ' | jq '.[]'

# | jq --arg action "vm_list" '
#         .plays[].tasks[]
#         | .hosts[]
#         | select(type=="object" and has($action))
#         | .[$action]
#         '

# ) | jq --arg action "$ARG_ACTION" '
#         .plays[].tasks[]
#         | .hosts[]
#         | select(type=="object" and has($action))
#         | .[$action]
#       '
