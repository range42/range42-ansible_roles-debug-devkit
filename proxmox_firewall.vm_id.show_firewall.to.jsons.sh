#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_firewall.vm_id.show_firewall.to.jsons.sh
#
# The show_firewall view at one grain : one guest, its id on stdin or as the argument.
# A thin wrapper : it execs the engine proxmox_firewall.show_firewall.to.jsons.sh with
# --scope vm_id, and nothing else. The engine carries the context guard, the api fast
# path, the ansible slow path and the three outputs (--json, --text, --table).
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "    $(basename "$0") 2001 --table"
  echo "    echo 2001 | $(basename "$0")"
  echo "    echo '{"vm_id":2001}' | $(basename "$0") --text"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the show_firewall view, one guest, its id on stdin or as the argument "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help]"
  echo "  [STDIN :: ids] | $(basename "$0") [--json|--text|--table]"
  echo
  echo "  same lines and same outputs as proxmox_firewall.show_firewall.to.jsons.sh (see its --help), scope fixed to vm_id"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

exec proxmox_firewall.show_firewall.to.jsons.sh --scope vm_id "$@"
