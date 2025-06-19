#!/bin/bash

#
# todo look for vault-agent project
#

####
#### TO TEST  : https://github.com/range42/range42-private-installer/issues/30
####

set -euo pipefail

DEFAULT_OPEN_VAULT_PW_FILE_PATH="/tmp/vault/vault_pass.txt"
VAULT_FILE="$RANGE42_ANSIBLE_ROLES__DEVKITS_DIR/secrets/px-testing.cr42_tailscale.yaml"
# VAULT_FILE="./secrets/px-testing.cr42_tailscale.yaml"



if ! [[ -f $DEFAULT_OPEN_VAULT_PW_FILE_PATH ]]; then

    OPEN_VAULT_PW_FILE_PATH=$(devkit_ansible.open_vault.to.file.sh)

fi

if ! [[ -f $DEFAULT_OPEN_VAULT_PW_FILE_PATH ]]; then
    OPEN_VAULT_PW_FILE_PATH=$(devkit_ansible.open_vault.to.file.sh)
    DEFAULT_OPEN_VAULT_PW_FILE_PATH=$OPEN_VAULT_PW_FILE_PATH

fi

PROXMOX_NODE=$(
    ansible-vault view --vault-password-file "$DEFAULT_OPEN_VAULT_PW_FILE_PATH" "$VAULT_FILE" |
        yq -r '.proxmox_node'
)
echo "$PROXMOX_NODE"
