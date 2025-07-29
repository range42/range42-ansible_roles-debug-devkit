#!/bin/bash

# ISSUE - 105

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="cloudinit_set_variables"
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
    '{ "vm_id": 2222, "proxmox_node": "px-testing", "vm_ci_user": "test", "vm_ci_password" : "supersecret...", "vm_ci_ssh_key": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA....", "vm_ci_dns_ips": "1.1.1.1", "vm_ci_ip" : "192.168.42.217", "vm_ci_netmask": "24", "vm_ci_ip_gw": "192.168.42.1" }'
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
  echo "  $(basename "$0") - set cloud init var on  VM or TEMPLATE - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                         $(basename "$0") [-h|--help]"
  echo "  echo [STORAGE_NAME]  | $(basename "$0") [--json]        - force output as json "
  echo "  echo [STORAGE_NAME]  | $(basename "$0") [--text]        - force output as text (debug purpose)"
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
  devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::vm_id" "STR::proxmox_node" "STR::action"
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
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" | jq -c "."
    # jq -c '.[]'

  else
    # text output mode  - debug

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
