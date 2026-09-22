#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# arm the firewall of guests : ssh accept, card flags, then the switch, in that order
#
# A thin wrapper : the whole sequence lives in proxmox__inc.firewall_arm.to.jsons.sh so the
# four arming composites cannot drift apart. Every step is a unitary devkit that takes the api
# fast path when the api answers ; RANGE42_PROXMOX_API_FORCE=off keeps every step on ansible.
#
# Ids on stdin, one per line. For every guest, in order : the ssh accept is posted (or found),
# then every card is flagged, then the guest switch goes on ; the guest is read back and a guest
# that is not set up to filter is refused. A guest the node does not run is skipped and named ;
# a guest with no card refuses the run before anything is written. The datacenter switch is the
# third condition and is not touched here : proxmox_firewall.proxmox_node.arm.to.jsons.sh
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "  printf '%s\\n' 2001 2002 | $(basename "$0")"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - arm the firewall of guests : ssh accept, card flags, then the switch, in that order"
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help]"
  echo "  $(basename "$0") [--json]      - one json line per unitary step, then one summary line per target *default"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

case "${1:-}" in
  ""|--json) ;;
  *) devkit_utils.text.echo_error.to.text.to.stderr.sh "unknown arg '$1'" ; show_example >&2 ; exit 1 ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

exec proxmox__inc.firewall_arm.to.jsons.sh guests-arm
