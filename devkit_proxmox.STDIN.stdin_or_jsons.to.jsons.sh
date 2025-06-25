#!/bin/bash

# PR-19

extract_new_key_field_name_from_stdin() {

    local FIRST_ARG="$1"

    if [[ "$FIRST_ARG" != *"::"* ]]; then

        devkit_utils.text.echo_error.to.text.to.stderr.sh "Invalid ARGUMENT $FIRST_ARG"
        return 1
    fi

    printf '%s' "${FIRST_ARG#*::}"
}

# VAULT_NODE=$(printf "%s\n" "$(devkit_ansible.get_proxmox_node.to.jsons.sh)")
# NEW_KEY_FIELD_NAME_FROM_STDIN=$(extract_new_key_field_name_from_stdin "$1")
#
# if [ ! -t 0 ]; then
#     JSON_LINE_REQ=$(
#         cat - |
#             jq -R -c ' fromjson? //  {"proxmox_node": .}' | # CONVERT STDIN TEXT (left) TO JSON OR CONTINUE WITH JSON (right)
#             jq -c --arg vault_node "$VAULT_NODE" --arg action "$ACTION" '
#                 .proxmox_node //= $vault_node |
#                 .action = $action
#             ' |
#             devkit_proxmox.STDIN.normalize.to.jsons.sh "$@" | # "STR::proxmox_node" "STR::action" |
#             jq -c "."
#     )
# else ### if proxmox_node not specified, we take the default value from the vault.

#     JSON_LINE_REQ=$(
#         printf "%s\n" "$VAULT_NODE" |
#             jq -R -c ' fromjson? //  {"proxmox_node": .}' | # CONVERT STDIN TEXT (left) TO JSON OR CONTINUE WITH JSON (right)
#             jq -c --arg vault_node "$VAULT_NODE" --arg action "$ACTION" '
#                 .proxmox_node //= $vault_node |
#                 .action = $action
#             ' |
#             devkit_proxmox.STDIN.normalize.to.jsons.sh "$@" | # "STR::proxmox_node" "STR::action" |
#             jq -c "."
#     )
# fi

VAULT_NODE=$(printf "%s\n" "$(devkit_ansible.get_proxmox_node.to.jsons.sh)")
NEW_KEY_FIELD_NAME_FROM_STDIN=$(extract_new_key_field_name_from_stdin "$1")

#
# COMPACT VERSION.
#

JSON_LINE_REQ=$(

    { [ -t 0 ] && printf "%s\n" "$VAULT_NODE" || cat -; } |
        jq -R -c --arg key "$NEW_KEY_FIELD_NAME_FROM_STDIN" '
            (fromjson? // .) as $v_to_evaluate |
                if ($v_to_evaluate | type) == "object" then
                    $v_to_evaluate
                else
                    { ($key): $v_to_evaluate }
                end
                ' | jq -c --arg vault_node "$VAULT_NODE" --arg action "$ACTION" '
                    .proxmox_node //= $vault_node |
                    .action = $action
            ' |
        jq -c "."
)
# OLDER VERSION - not matching correctly json object
# #

#     { [ -t 0 ] && printf "%s\n" "$VAULT_NODE" || cat -; } |
#         jq -R -c "fromjson? // . | {\"$NEW_KEY_FIELD_NAME_FROM_STDIN\": .}" | # CONVERT STDIN TEXT (left) TO JSON OR CONTINUE WITH JSON (right)
#         jq -c --arg vault_node "$VAULT_NODE" --arg action "$ACTION" '
#             .proxmox_node //= $vault_node |
#             .action = $action
#             ' |
#         devkit_proxmox.STDIN.normalize.to.jsons.sh "$@" |
#         jq -c "."

#
# NOTES :
#
# THIS WILL NOT WORK WITH INT :
#   ### jq -R -c "fromjson? // {\"$NEW_KEY_FIELD_NAME_FROM_STDIN\": .}" | # CONVERT STDIN TEXT (left) TO JSON OR CONTINUE WITH JSON (right)
#
# DONT REMOVE THE DOT :
#   #### echo 42 | jq -R -c 'fromjson? // . | {new: .}'
#

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r NODE_JSON; do

    printf '%s\n' "$NODE_JSON"
done
