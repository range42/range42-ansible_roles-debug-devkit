#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# arm the host firewall : management access first, then the datacenter switch, then the node switch
#
# A thin wrapper : the whole sequence lives in proxmox__inc.firewall_arm.to.jsons.sh so the
# four arming composites cannot drift apart. Every step is a unitary devkit that takes the api
# fast path when the api answers ; RANGE42_PROXMOX_API_FORCE=off keeps every step on ansible.
#
# No stdin. The management accepts (8006, 22) are guaranteed at the datacenter and at the node
# before either switch goes on ; both guards refuse to arm a level whose management ports are not
# accepted. From that moment every guest already armed on this host filters.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "  $(basename "$0")"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - arm the host firewall : management access first, then the datacenter switch, then the node switch"
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

exec proxmox__inc.firewall_arm.to.jsons.sh host-arm
