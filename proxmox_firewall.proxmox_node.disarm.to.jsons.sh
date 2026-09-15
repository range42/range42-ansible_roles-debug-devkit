#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# disarm the host firewall : the datacenter switch off, then the node switch ; the accepts are kept
#
# A thin wrapper : the whole sequence lives in proxmox__inc.firewall_arm.to.jsons.sh so the
# four arming composites cannot drift apart. Every step is a unitary devkit that takes the api
# fast path when the api answers ; RANGE42_PROXMOX_API_FORCE=off keeps every step on ansible.
#
# No stdin. The datacenter switch is the master switch of the host : off, nothing filters anywhere
# on it, the guests of every scenario included. They keep their own switch and card flags, and
# filter again the moment the host is re-armed. The management accepts are kept, on purpose.
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
  echo "  $(basename "$0") - disarm the host firewall : the datacenter switch off, then the node switch ; the accepts are kept"
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

exec proxmox__inc.firewall_arm.to.jsons.sh host-disarm
