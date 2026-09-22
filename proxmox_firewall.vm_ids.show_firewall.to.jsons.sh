#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_firewall.vm_ids.show_firewall.to.jsons.sh
#
# The show_firewall view at one grain : a set of guests, one id per line on stdin (plain or json), duplicates folded, order kept.
# A thin wrapper : it execs the engine proxmox_firewall.show_firewall.to.jsons.sh with
# --scope vm_ids, and nothing else. The engine carries the context guard, the api fast
# path, the ansible slow path and the three outputs (--json, --text, --table).
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "    printf '2001\\n2002\\n' | $(basename "$0") --table"
  echo "    proxmox_vm.list.to.jsons.sh | jq -c 'select(.vm_tags == \"blank\")' | $(basename "$0")"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the show_firewall view, a set of guests, one id per line on stdin (plain or json), duplicates folded, order kept "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help]"
  echo "  [STDIN :: ids] | $(basename "$0") [--json|--text|--table]"
  echo
  echo "  same lines and same outputs as proxmox_firewall.show_firewall.to.jsons.sh (see its --help), scope fixed to vm_ids"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

exec proxmox_firewall.show_firewall.to.jsons.sh --scope vm_ids "$@"
