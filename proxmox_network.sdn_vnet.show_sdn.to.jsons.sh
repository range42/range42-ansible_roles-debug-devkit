#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_network.sdn_vnet.show_sdn.to.jsons.sh
#
# The sdn view at one grain : ONE network, by its name. A thin wrapper : it execs the engine
# proxmox_network.show_sdn.to.jsons.sh with --scope sdn_vnet, and nothing else. The engine carries
# the context guard, the api fast path, the ansible slow path and the three outputs (--json,
# --text, --table).
#
# A legacy vmbr bridge is not an SDN object : its live rules only count when its cidr comes with
# the name, {"vnet":"vmbr142","cidr":"192.168.142.0/24"} on stdin.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "    $(basename "$0") net143 --table"
  echo "    echo net143 | $(basename "$0") --json"
  echo "    devkit_utils.text.echo_json_helper.to.text.sh '{\"vnet\":\"vmbr142\",\"cidr\":\"192.168.142.0/24\"}' | $(basename "$0") --table"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the declared sdn of ONE network beside the live rules that forward it "
  echo
  echo OPTIONS
  echo
  echo "                      $(basename "$0") [-h|--help]"
  echo "  [STDIN :: network] | $(basename "$0") [--json|--text|--table] [vnet]"
  echo
  echo "  same lines and same outputs as proxmox_network.show_sdn.to.jsons.sh (see its --help), scope fixed to sdn_vnet"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

exec proxmox_network.show_sdn.to.jsons.sh --scope sdn_vnet "$@"
