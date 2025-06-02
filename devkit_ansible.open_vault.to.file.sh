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

###
###
###

# TO TEST :

# # 1) Lire la passphrase Vault en masqué (mode interactif)
# read -s -p "Mot de passe Vault : " VAULT_PASS
# echo

# # 2) Chiffrer VAULT_PASS via la clé publique, et récupérer le résultat dans VAULT_PASS_ENC
# VAULT_PASS_ENC=$(
#   printf "%s" "$VAULT_PASS" | \
#   ssh-keygen -Y encrypt -n vault-id -f ~/.ssh/id_rsa.pub
# )

# # VAULT_PASS_ENC contient maintenant le blob chiffré (en base64 ou binaire)

# # 3) Déchiffrer VAULT_PASS_ENC via la clé privée chargée par ssh-agent/Keychain
# VAULT_PASS_CLEAR=$(
#   printf "%s" "$VAULT_PASS_ENC" | \
#   ssh-keygen -Y decrypt -n vault-id -f ~/.ssh/id_rsa
# )

# # VAULT_PASS_CLEAR contient maintenant en clair votre mot de passe Vault
