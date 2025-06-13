#!/bin/bash

showExample() {

  echo "  $(basename "$0") storage_list_iso"
  echo "  $(basename "$0") storage_list_template"

}

if [ "$1" = '-h' ] ||
  [ "$1" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - LIB / INCLUDE script providing basic generic helper func for start|stop|pause|ect proxmox"
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] [URL]"
  echo "  $(basename "$0") [ACTION]   "

  echo
  echo EXAMPLE
  echo
  echo "$(showExample)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ROLE_NAME="range42-ansible_roles-proxmox_controller"
# DEFAULT_OUTPUT_JSON=true
DEFAULT_OPEN_VAULT_PW_FILE_PATH="/tmp/vault/vault_pass.txt"

# CURRENT_ANSIBLE_CONFIG="./ansible_no_skipped_json.cfg"
# CURRENT_ANSIBLE_CONFIG="./ansible_no_skipped.cfg"
# CURRENT_ANSIBLE_CONFIG="./ansible.cfg"
CURRENT_ANSIBLE_CONFIG="$RANGE42_ANSIBLE_ROLES__DEVKITS_DIR/ansible.cfg"

ARG_ACTION="${1:-}"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh
proxmox__inc.basic_vm_actions_warmup_checks.to.sh "$ARG_ACTION"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# open vault - look for ansible-agent
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

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

# note <<-EOF - delete should remove tab from pass to stdin.

(
  # ANSIBLE_CONFIG="./ansible_no_skipped_json.cfg"

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
)
