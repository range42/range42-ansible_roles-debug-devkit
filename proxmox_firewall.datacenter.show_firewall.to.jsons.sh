#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_firewall.datacenter.show_firewall.to.jsons.sh
#
# The show_firewall view at one grain : the whole datacenter, today the node of the vault (one node per workspace).
# A thin wrapper : it execs the engine proxmox_firewall.show_firewall.to.jsons.sh with
# --scope dc, and nothing else. The engine carries the context guard, the api fast
# path, the ansible slow path and the three outputs (--json, --text, --table).
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "    $(basename "$0") --table"
  echo "    $(basename "$0") --text"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the show_firewall view, the whole datacenter, today the node of the vault (one node per workspace) "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help]"
  echo "                   $(basename "$0") [--json|--text|--table]"
  echo
  echo "  same lines and same outputs as proxmox_firewall.show_firewall.to.jsons.sh (see its --help), scope fixed to dc"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

exec proxmox_firewall.show_firewall.to.jsons.sh --scope dc "$@"
