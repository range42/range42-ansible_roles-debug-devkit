#!/bin/bash

# ISSUE - 92

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="storage_download_iso"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"url\" | $(basename "$0") "
  echo "    echo \"url\" | $(basename "$0") --json"
  echo "    echo \"url\" | $(basename "$0") --text"
  echo
  echo "    cat /tmp/url.text | $(basename "$0")"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"proxmox_storage":"local", "iso_file_content_type":"iso","iso_file_name":"alpine-standard-3.22.0-x86_64.iso",                               "iso_url":"https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-standard-3.22.0-x86_64.iso"}'
    '{"proxmox_storage":"local", "iso_file_content_type":"iso","iso_file_name":"ubuntu-24.04-minimal-cloudimg-amd64.img","iso_url":"https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"}'
    '{"proxmox_storage":"local","iso_file_content_type":"iso", "iso_url":"https://cloud-images.ubuntu.com/minimal/daily/noble/current/noble-minimal-cloudimg-amd64.img", "iso_file_name": "noble-minimal-cloudimg-amd64.img"}'
    '{"proxmox_storage":"local","iso_file_content_type":"iso", "iso_url":"https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img", "iso_file_name": "noble-server-cloudimg-amd64.img"}'
    '{"proxmox_storage":"local","iso_file_content_type":"iso", "iso_url":"https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.raw", "iso_file_name": "debian-12-genericcloud-amd64.img"}'
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
  echo "  $(basename "$0") - list iso in storage                - Execute the specified $ACTION action via Ansible "
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
