#!/bin/bash

#
# Declare ONE service port on a guest : an ACCEPT posted only if none already grants it.
# Idempotent by construction - rule creation inserts at the top and ignores pos, so the
# role action re-reads the chain and skips when an active accept already sits above the
# first covering deny. The report carries `vm_fw_already_present` : a second identical
# run MUST say true, that is the idempotence witness.
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_vm_declare_iptables_port"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo
  echo "     vm_fw_dport is REQUIRED and numeric - the action refuses a missing or"
  echo "     malformed port instead of posting something else."
  echo

  local STDIN_JSON_DATA=(
    '{"vm_id":100,"vm_fw_dport":"8065"}'
    '{"vm_id":100,"vm_fw_dport":"8065","vm_fw_proto":"tcp"}'
    '{"vm_id":100,"vm_fw_dport":"53","vm_fw_proto":"udp"}'
    '{"vm_id":100,"vm_fw_dport":"55000","vm_fw_source":"192.168.143.0/24","vm_fw_comment":"agents to manager api"}'
    '{"vm_id":100,"proxmox_node":"px-testing","vm_fw_dport":"8443"}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --json"

  echo ""
  echo "  a source-restricted accept does NOT count as granting an unrestricted request,"
  echo "  and an accept on another proto does not count either - each shape is declared"
  echo "  on its own."
  echo ""
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Declare one service port - vm firewall - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                     $(basename "$0") [-h|--help] "
  echo "  STDIN :: [JSON]  | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [JSON]  | $(basename "$0") [--text]    - force output as text"
  echo ""
  echo EXAMPLE
  echo
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

case "${1:-}" in
--json)
  OUTPUT_JSON=true
  ;;
--text)
  OUTPUT_JSON=false
  ;;
"") ;;
*)
  devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
  show_example
  exit 1
  ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION"

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
