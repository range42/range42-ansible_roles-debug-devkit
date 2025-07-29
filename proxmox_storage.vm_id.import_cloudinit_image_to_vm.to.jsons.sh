#!/bin/bash

# ISSUE - 105

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="template_cloudinit_import_disk"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"JSON_DATA\" | $(basename "$0") "
  echo "    echo \"JSON_DATA\" | $(basename "$0") --json"
  echo "    echo \"JSON_DATA\" | $(basename "$0") --text"
  echo
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"proxmox_node": "px-testing-cli", "cloudinit_image_full_path": "/var/lib/vz/template/iso/ubuntu-24.04-minimal-cloudimg-amd64.img", "vm_id":2222, "vm_disk_size": "32g", "dest_proxmox_storage":"local-lvm"}'

  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  echo ""

}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - import cloudinit images             - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                         $(basename "$0") [-h|--help]"
  echo "  echo [STORAGE_NAME]  | $(basename "$0") [--json]      - force output as json "
  echo "  echo [STORAGE_NAME]  | $(basename "$0") [--text]      - force output as text (debug purpose)"
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
  *) ;;

  esac

done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JSON_LINE_REQ=$(
  devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh \
    "STR::iso_url" "STR::iso_file_content_type" "STR::iso_file_name" \
    "STR::proxmox_storage" "STR::proxmox_node" "STR::action"
)

echo $JSON_LINE_REQ

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  #
  # CURRENT_JSON_LINE=$NEW_CURRENT_JSON_LINE
  devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"
  # exit 1

  if [[ "$OUTPUT_JSON" == true ]]; then # JSON output mode.

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" #|
    # jq -c '.[]'

  else
    # text output mode  - debug

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
