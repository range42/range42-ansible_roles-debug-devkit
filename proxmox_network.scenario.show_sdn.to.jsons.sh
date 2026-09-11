#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_network.scenario.show_sdn.to.jsons.sh
#
# The sdn view at one grain : the networks the ACTIVE SCENARIO declares, read as the bridges of its
# workspace manifest. A thin wrapper : it execs the engine proxmox_network.show_sdn.to.jsons.sh
# with --scope scenario, and nothing else. The engine carries the context guard, the api fast path,
# the ansible slow path and the three outputs (--json, --text, --table).
#
# A MANIFEST HOLDS NO CIDR, and nothing here derives one from a bridge name. A scenario built on
# SDN networks gets its cidrs from the subnets and its rules counted. A scenario built on legacy
# vmbr bridges gets its rows with no cidr, so its counts stay unknown : range42-context, which
# resolves the manifest, passes the cidrs it knows through the sdn_vnets grain instead.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "    $(basename "$0") --table"
  echo "    $(basename "$0") --json | jq -c 'select(.internet == \"YES\")'"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the declared sdn of the networks of the active scenario, beside their live rules "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help]"
  echo "  $(basename "$0") [--json|--text|--table]"
  echo
  echo "  same lines and same outputs as proxmox_network.show_sdn.to.jsons.sh (see its --help), scope fixed to scenario"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

exec proxmox_network.show_sdn.to.jsons.sh --scope scenario "$@"
