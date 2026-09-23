#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# disarm the firewall of guests : the switch off, then the card flags ; the ssh accept is kept
#
# A thin wrapper : the whole sequence lives in proxmox__inc.firewall_arm.to.jsons.sh so the
# four arming composites cannot drift apart. Every step is a unitary devkit that takes the api
# fast path when the api answers ; RANGE42_PROXMOX_API_FORCE=off keeps every step on ansible.
#
# Ids on stdin, one per line. For every guest, in order : the guest switch goes off, then every
# card is unflagged, then the ssh accept is re-posted so a later arming stays safe. MAC spoofing
# becomes possible again on the cards touched : one flag carries both, they do not split.
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
  echo "  $(basename "$0") - disarm the firewall of guests : the switch off, then the card flags ; the ssh accept is kept"
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

exec proxmox__inc.firewall_arm.to.jsons.sh guests-disarm
