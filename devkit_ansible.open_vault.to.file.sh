#!/bin/bash

#
# todo look for vault-agent project
#

OPEN_VAULT_PW_FILE_PATH="/tmp/vault/vault_pass.txt"
OPEN_VAUlT_DIR=$(dirname "$OPEN_VAULT_PW_FILE_PATH")
#

read -s -p " :: VAULT PWD : " VAULT_PWD

mkdir -p "$OPEN_VAUlT_DIR"
echo "$VAULT_PWD" >"$OPEN_VAULT_PW_FILE_PATH"

chmod 600 "$OPEN_VAULT_PW_FILE_PATH"
echo "$OPEN_VAULT_PW_FILE_PATH"

####
#### TO TEST  : https://github.com/range42/range42-private-installer/issues/30
####
