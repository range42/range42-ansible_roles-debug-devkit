#!/bin/bash

#
# PR-58
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_vm_iface_disable"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: vm_vmnet_id IS REQUIRED, so a bare vm_id is not enough"
  echo
  echo "     It is the N of netN, and it is asked for explicitly on purpose : a VM with"
  echo "     several cards would otherwise have the wrong one touched. There is no default."
  echo
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"vm_id":100,"vm_vmnet_id":0}'
    '{"proxmox_node":"px-testing", "vm_id":100, "vm_vmnet_id":0}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --json"

  echo ""
  echo "  :: WHAT IT DOES, AND WHAT IT DOES NOT"
  echo
  echo "     It sets firewall=0 on the card, by editing the net<N> string it read - so the MAC,"
  echo "     the VLAN tag, the MTU and every other setting are left untouched. It reads the card"
  echo "     back twice, stored AND running, and refuses to report a success that is not one."
  echo
  echo "     It also hands MAC SPOOFING BACK : the same flag carries the anti-spoof, and this is the only way to ask for a spoofable card. A card is either filtered or free to spoof, never both."
  echo
  echo "  :: SEE ALSO"
  echo
  echo "     proxmox_firewall.vm_id.enable_firewall.to.jsons.sh - the guest switch, one level up"
  echo "     proxmox_firewall.vm_id.effective_filtering_state.to.jsons.sh - what actually filters"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Disable the firewall flag of ONE network card of a vm - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                     $(basename "$0") [-h|--help] "
  echo "  STDIN :: [VM_ID] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [VM_ID] | $(basename "$0") [--text]    - force output as text"
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

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "INT::vm_id" "INT::vm_vmnet_id" "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  # enrich json with vm_name
  VM_NAME=$(
    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox_vm.vm_id.list_vm_and_extract_vm_name.to.jsons.sh |
      jq -r '.vm_name // empty'
  )

  # merge jsons

  NEW_CURRENT_JSON_LINE=$(
    printf '%s\n' "$CURRENT_JSON_LINE" |
      jq -c --arg jq_vm_name_v "$VM_NAME" '. + { ("vm_name"): $jq_vm_name_v }'
  )

  # update current json line
  CURRENT_JSON_LINE=$NEW_CURRENT_JSON_LINE

  # devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"
  # exit 0

  if [[ "$OUTPUT_JSON" == true ]]; then

    # The shared normaliser keeps only the key named after the action, and that key is built
    # by the last task of the play. So when the play stops early nothing reaches stdout, and
    # the role's own message is discarded upstream of here : do not look for it in this file.
    _dk_rc=0
    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" || _dk_rc=$?

    if [ "$_dk_rc" -ne 0 ]; then
      devkit_utils.text.echo_error.to.text.to.stderr.sh \
        "stopped without printing anything (rc=${_dk_rc}). TWO causes are possible and they are NOT the same : the guard refused BEFORE touching anything, or the change went through and a later step failed."
      devkit_utils.text.echo_error.to.text.to.stderr.sh \
        "read THE CARD to tell them apart, not the guest switch : proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh . On the card you named, a vm_network_firewall of 1 means nothing was changed. A 0 means the flag IS cleared despite this error, and only the reporting failed. Then run the same command with --text to see which step stopped the play."
      devkit_utils.text.echo_error.to.text.to.stderr.sh \
        "do NOT read the guest switch here. This action never touches it, so its value says nothing about this call : it can read 1 for reasons entirely unrelated to the card flag."
      exit "$_dk_rc"
    fi

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
