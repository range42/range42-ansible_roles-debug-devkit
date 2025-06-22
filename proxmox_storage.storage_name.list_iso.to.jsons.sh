#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# PR-29
set -euo pipefail
ACTION="storage_list_iso"
DEFAULT_OUTPUT_JSON=true
ARG_STORAGE_NAME=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"local\" | $(basename "$0") "
  echo "    echo \"local\" | $(basename "$0") --json"
  echo "    echo \"local\" | $(basename "$0") --text"
  echo
  echo "    cat /tmp/storage_name.text | $(basename "$0")"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"storage_name":"local"}'
    '{"storage_name":"local","proxmox_node":"px-testing"}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") local --json"

  echo ""
  echo "    cat /tmp/storage_name.json | $(basename "$0")"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - list iso in storage  - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                         $(basename "$0") [-h|--help]"
  echo "  echo [STORAGE_NAME]  | $(basename "$0") [--json]                                    - force output as json "
  echo "  echo [STORAGE_NAME]  | $(basename "$0") [partial_or_complete_storage_name] [--json] - force output in JSON format with a case insensitive filter on the storage name"
  echo "  echo [STORAGE_NAME]  | $(basename "$0") [--text]                                    - force output as text (debug purpose)"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

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
    show_example
    exit 1
    ;;
  *)
    if [[ -z "$ARG_STORAGE_NAME" ]]; then
      ARG_STORAGE_NAME="$1"
      shift
    else
      devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
      show_example
      exit 1
    fi
    ;;
  esac
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::storage_name" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r NODE_JSON; do

  if [[ "$OUTPUT_JSON" == true ]]; then # JSON output mode.

    if [[ -n "$ARG_STORAGE_NAME" ]]; then # with filter on keyfield

      printf '%s\n' "$NODE_JSON" |
        proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" |
        jq -c '.[]' |
        devkit_transform.jsons.key_field_greper.to.jsons.sh "storage_name" "$ARG_STORAGE_NAME"

    else # not filter in argument

      printf '%s\n' "$NODE_JSON" |
        proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" |
        jq -c '.[]'

    fi

  else # text output mode  - debug

    printf '%s\n' "$NODE_JSON" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
