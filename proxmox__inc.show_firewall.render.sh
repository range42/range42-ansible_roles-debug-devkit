#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox__inc.show_firewall.render.sh json|text|table
#
# Shared by the show_firewall engine and its _with_api twin : reads the json lines of the
# view on stdin (levels host, card, guest, absent, error) and prints them in the asked form.
#
#   json    the lines as they are
#   text    one line of words per json line, the words of the per-vm reader
#   table   the host sentence, the cards through devkit_utils.jsons.render.to.table.sh,
#           then the guests without a card, the ids the node does not run, the unreadable ones
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - shared renderer of the show_firewall engine and its twin "
  echo
  echo OPTIONS
  echo
  echo "  STDIN :: jsons | $(basename "$0") json|text|table"
  echo
  echo
  exit 1
fi

MODE="${1:-json}"
case "$MODE" in
json | text | table) ;;
*)
  devkit_utils.text.echo_error.to.text.to.stderr.sh " unknown output : ${MODE} (json, text or table)"
  exit 1
  ;;
esac

# NOT "LINES" : bash and zsh own that name (the terminal height) and bash rewrites it after every
# external command when a terminal is attached, so the second pipeline below would receive a number.
# Invisible in piped tests, seen live on a deployer.
VIEW_JSON=$(cat)

if [[ "$MODE" == "json" ]]; then
  [ -n "$VIEW_JSON" ] && printf '%s\n' "$VIEW_JSON"
  exit 0
fi

if [[ "$MODE" == "text" ]]; then
  [ -n "$VIEW_JSON" ] && printf '%s\n' "$VIEW_JSON" | jq -r '
    if .level == "host" then
      "node \(.proxmox_node) : datacenter switch \(.datacenter_enable // "-"), node switch \(.node_enable // "-")"
    elif .level == "card" then
      "vm \(.vm_id) (\(.vm_name))  \(.vm_network_device)  bridge=\(.vm_network_bridge // "?")  dc=\(.datacenter_enable // "-")  node=\(.node_enable // "-")  guest=\(.guest_enable // "-")  card=\(.card_firewall_flag // "-")  filtered=\(.effectively_filtered)"
      + (if (.missing | length) > 0 then "   off: \(.missing | join(", "))" else "" end)
    elif .level == "guest" then
      "vm \(.vm_id) (\(.vm_name)) : no network card"
    elif .level == "absent" then
      "vm \(.vm_id) : not on this node"
    elif .level == "error" then
      "vm \(.vm_id) : unreadable (\(.reason))"
    else tojson end'
  exit 0
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# table
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

[ -n "$VIEW_JSON" ] || exit 0

printf '%s\n' "$VIEW_JSON" | jq -r 'select(.level == "host")
  | "  node \(.proxmox_node) : datacenter switch \(.datacenter_enable // "-"), node switch \(.node_enable // "-")\n"'

printf '%s\n' "$VIEW_JSON" | jq -c 'select(.level == "card")' |
  devkit_utils.jsons.render.to.table.sh vm_id:VM_ID vm_name:VM_NAME guest_enable:GUEST vm_network_device:CARD vm_network_bridge:BRIDGE card_firewall_flag:FLAG effectively_filtered:FILTERED

NO_CARD=$(printf '%s\n' "$VIEW_JSON" | jq -r 'select(.level == "guest") | .vm_id' | paste -sd ' ' -)
ABSENT=$(printf '%s\n' "$VIEW_JSON" | jq -r 'select(.level == "absent") | .vm_id' | paste -sd ' ' -)
ERRORS=$(printf '%s\n' "$VIEW_JSON" | jq -r 'select(.level == "error") | "  unreadable : vm \(.vm_id) (\(.reason))"')

[ -z "$NO_CARD" ] || printf '\n  no network card : %s\n' "$NO_CARD"
[ -z "$ABSENT" ] || printf '\n  not on this node : %s\n' "$ABSENT"
[ -z "$ERRORS" ] || printf '\n%s\n' "$ERRORS"
echo ""
