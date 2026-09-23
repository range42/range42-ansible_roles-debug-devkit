#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_firewall.vm_id.show_firewall_rules.to.jsons.sh
#
# The firewall rules at one grain : the datacenter, the node, and one guest.
# A thin wrapper : it execs the engine proxmox_firewall.show_firewall_rules.to.jsons.sh with
# --scope vm_id, and nothing else. The engine carries the context guard, the api fast path,
# the ansible slow path and the three outputs (--json, --text, --table). The rules of the
# datacenter and of the node come with every scope, they apply to every guest.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "    $(basename "$0") 2001 --table"
  echo "    echo 2001 | $(basename "$0") --text"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the firewall rules, the datacenter, the node, and one guest "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help]"
  echo "  [STDIN :: ids] | $(basename "$0") [--json|--text|--table]"
  echo
  echo "  same lines and same outputs as proxmox_firewall.show_firewall_rules.to.jsons.sh (see its --help), scope fixed to vm_id"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

exec proxmox_firewall.show_firewall_rules.to.jsons.sh --scope vm_id "$@"
