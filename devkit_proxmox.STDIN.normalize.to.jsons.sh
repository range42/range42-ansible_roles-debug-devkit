#!/bin/bash

parse_stdin_schema() {
    local SCHEMA=("$@")
    local STDIN_DATA KEY_NAME KEY_TYPE
    local SIMPLE_VALUE SIMPLE_TYPE
    local KV_PAIR=()

    if [ -t 0 ]; then
        devkit_utils.text.echo_error.to.text.to.stderr.sh "NO STDIN !"
        return 1
    fi

    STDIN_DATA=$(cat -)

    if [[ "$STDIN_DATA" =~ ^[0-9]+$ ]]; then
        SIMPLE_TYPE="INT"
        SIMPLE_VALUE="$STDIN_DATA"

    elif [[ "$STDIN_DATA" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        SIMPLE_TYPE="STR"
        SIMPLE_VALUE="$STDIN_DATA"
    fi

    #
    # PURE TEXT CASE
    #

    if [[ "$STDIN_DATA" =~ ^[0-9]+$ ]] || [[ "$STDIN_DATA" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        for field in "${SCHEMA[@]}"; do
            KEY_TYPE="${field%%::*}" # STR or INT - reminder - equal to  | sed 's/::.*//' extract before ::
            KEY_NAME="${field##*::}" # Value      - reminder - equal to  | sed 's/.*:://' extract after ::

            case "$KEY_TYPE" in
            STR)
                # STRING CASE :
                printf '{"%s": "%s"}\n' "$KEY_NAME" "$STDIN_DATA"
                return 0
                ;;
            INT)
                # INT CASE :
                if [[ "$STDIN_DATA" =~ ^[0-9]+$ ]]; then
                    printf '{"%s": %s}\n' "$KEY_NAME" "$STDIN_DATA"
                    return 0
                fi
                ;;
            *)
                devkit_utils.text.echo_error.to.text.to.stderr.sh "Unsupported type '$KEY_TYPE'"

                return 1
                ;;
            esac
        done

        devkit_utils.text.echo_error.to.text.to.stderr.sh "No maching key in input '$STDIN_DATA'"

        return 1
    fi

    #
    # JSON CASE
    #

    if ! echo "$STDIN_DATA" | jq -e 'type == "object"' >/dev/null 2>&1; then

        devkit_utils.text.echo_error.to.text.to.stderr.sh "Invalid input. Should JSON line data."
        return 1
    fi

    #
    # CHECK MANDATORY FIELDS AND TYPE
    #

    for field in "${SCHEMA[@]}"; do

        KEY_TYPE="${field%%::*}" # reminder | sed 's/::.*//' extract before ::
        KEY_NAME="${field##*::}" # reminder | sed 's/.*:://' extract after ::

        #
        # key check
        #

        if ! echo "$STDIN_DATA" | jq -e --arg key "$KEY_NAME" 'has($key)' >/dev/null; then

            devkit_utils.text.echo_error.to.text.to.stderr.sh "Missing required key : '$KEY_NAME' "
            return 1
        fi

        #
        # type 'validation' for JSON
        #

        if ! echo "$STDIN_DATA" |
            jq -e --arg arg_jq_key "$KEY_NAME" --arg arg_jq_type "$KEY_TYPE" '
                (.[$arg_jq_key] != null) and
                ( 
                  ( ($arg_jq_type == "INT") and (.[$arg_jq_key]|type == "number") )
                  or
                  ( ($arg_jq_type == "STR") and (.[$arg_jq_key]|type == "string") )
                )
            ' >/dev/null; then

            devkit_utils.text.echo_error.to.text.to.stderr.sh "Key '$KEY_NAME' is not expected type as $KEY_TYPE"

            return 1
        fi

        #
        # build normalized output
        #

        KV_PAIR+=(
            "$(echo "$STDIN_DATA" |
                jq -c --arg k "$KEY_NAME" '.[$k] | {($k): .}')"
        )

    done

    #
    # merge data then print
    #

    jq -c -s 'add' <<<"${KV_PAIR[*]}"
}

# cat - | parse_stdin_schema "INT::vm_id" "STR::something"

IFS=$'\n'

while IFS=$'\n' read -r l; do
    # printf "%s" "$l" | parse_stdin_schema "STR::proxmox_node" # "STR::something"

    printf '%s\n' "$l" | parse_stdin_schema "$@"
done

# cat - | devkit_proxmox.STDIN.normalize.to.jsons.sh "STR::proxmox_node" "STR::something"
# cat - | devkit_proxmox.STDIN.normalize.to.jsons.sh "INT::vm_id" #"STR::something"
# cat - | devkit_proxmox.STDIN.normalize.to.jsons.sh "STR::vm_id" #"STR::something"
