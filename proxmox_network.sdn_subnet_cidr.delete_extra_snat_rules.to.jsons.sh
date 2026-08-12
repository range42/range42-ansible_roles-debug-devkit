#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# delete the extra live SNAT rules of one subnet, down to a wanted count
#
# Reconciles the LIVE iptables rules with the declared state. It is the one action of the
# role that is not an API call : it runs iptables on the node, because an SDN apply is not
# idempotent and adds one SNAT rule per active subnet every single time.
#
# >>> IT DELETES, IT NEVER CREATES <<<
# want=1 on a subnet with zero rules leaves zero, creating the rule is the apply job.
# want=0 cuts the subnet off from the outside.
#
# sdn_subnet_cidr must carry its mask, exactly as iptables renders it. The role asserts it
# and refuses a bare address, a short prefix such as 192.168.14, and the subnet id form.
# That guard matters : an unanchored match would hit every rule on the host.
#
# It matches on the source network, not on the target, so it handles SNAT and MASQUERADE
# alike. That is what makes it able to clean up the rules left by the legacy bridge hack.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="network_delete_extra_snat_rules"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"proxmox_node":"px-testing","sdn_subnet_cidr":"192.168.199.0/24","sdn_snat_want":1}'
    '{"proxmox_node":"px-testing","sdn_subnet_cidr":"192.168.199.0/24","sdn_snat_want":0}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --text"

  echo ""
  echo "    cat /tmp/sdn_requests.json | $(basename "$0")"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - delete the extra live SNAT rules of one subnet, down to a wanted count - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  $(basename "$0") [--json]      - force output as json "
  echo "  $(basename "$0") [--text]      - force output as text (debug purpose)"
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
#
# browse provided arugments :
#

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
#
# Every key below is REQUIRED : a write action with a missing field either fails on
# the API side with an unhelpful message, or worse, succeeds having changed nothing.
#
JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::sdn_subnet_cidr" "STR::sdn_snat_want" "STR::proxmox_node" "STR::action")
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"

  if [[ "$OUTPUT_JSON" == true ]]; then # json mode.

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION"

  else # text output mode  - debug

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
