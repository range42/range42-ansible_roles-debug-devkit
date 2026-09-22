#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_network.sdn_vnets.show_sdn.to.jsons.sh
#
# The sdn view at one grain : A SET of networks, one name per line on stdin. A thin wrapper : it
# execs the engine proxmox_network.show_sdn.to.jsons.sh with --scope sdn_vnets, and nothing else.
# The engine carries the context guard, the api fast path, the ansible slow path and the three
# outputs (--json, --text, --table).
#
# The order of the names is kept, duplicates are folded. A line is a bare name or a json object
# naming the network in vnet, subnet_vnet or bridge, with an optional cidr - so the subnets of the
# cluster pipe in as they come, and so does a list a caller resolved elsewhere.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "    printf 'net143\\nnet144\\n' | $(basename "$0") --table"
  echo "    proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh | $(basename "$0") --table"
  echo "    printf '%s\\n' '{\"vnet\":\"vmbr142\",\"cidr\":\"192.168.142.0/24\"}' | $(basename "$0") --json"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the declared sdn of A SET of networks beside the live rules that forward them "
  echo
  echo OPTIONS
  echo
  echo "                       $(basename "$0") [-h|--help]"
  echo "  [STDIN :: networks] | $(basename "$0") [--json|--text|--table]"
  echo
  echo "  same lines and same outputs as proxmox_network.show_sdn.to.jsons.sh (see its --help), scope fixed to sdn_vnets"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

exec proxmox_network.show_sdn.to.jsons.sh --scope sdn_vnets "$@"
