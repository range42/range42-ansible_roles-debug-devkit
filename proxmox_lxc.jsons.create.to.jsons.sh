#!/bin/bash

#
# PR-62
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
set -euo pipefail
ACTION="lxc_create"
DEFAULT_OUTPUT_JSON=true
# ARG_VM_SNAPSHOT_NAME=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {

  echo
  echo "    echo \"CONFIG_JSON\" | $(basename "$0") --json"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo "     cat ./vm_profiles/profile_01.json  | jq -c  | $(basename "$0")"
  echo

  local STDIN_JSON_DATA=(
    '{"vm_id":"800","lxc_name":"test_aaaaa","lxc_template":"local:vztmpl/alpine-3.19-default_20240207_amd64.tar.xz","lxc_password":"dGhpczRmb3J0ZXN0Cg==","lxc_ssh_pubkeys":"","lxc_cpu":"1","lxc_cores":"1","lxc_memory":"2048","proxmox_storage":"local-lvm","lxc_disk_size":"16","lxc_net_name":"eth0","lxc_bridge":"vmbr0","lxc_ip":"192.168.42.231","lxc_gateway":"192.168.42.1","lxc_dns_primary":"1.1.1.1","lxc_dns_secondary":"4.2.2.4"}'

  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --text"
  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --json"

  echo ""
  echo "    cat ./vm_profiles/sample_01.json | jq -c \".\" | $(basename "$0")"
  echo ""

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo
  echo "  $(basename "$0") - create LXC - require CONFIG_JSON  - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [--json]                                     - force output as json *default"
  echo "  STDIN :: [VM_ID] | $(basename "$0")  [--text]                                     - force output as text"
  echo ""

  echo EXAMPLE
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh
proxmox__inc.warmup_checks_stdin.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# define output type
#
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
    # if [[ -z "$ARG_VM_SNAPSHOT_NAME" ]]; then
    #   ARG_VM_SNAPSHOT_NAME="$1"
    #   shift
    # else
    # devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
    # show_example
    # exit 1
    # fi
    ;;
  esac
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR::vm_name" "STR::proxmox_node" "STR::action")

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR::lxc_name" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  # devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"
  # exit 1

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" #|

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
