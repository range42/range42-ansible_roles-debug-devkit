#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_network.datacenter.show_sdn.to.jsons.sh
#
# The sdn view at one grain : EVERY network the cluster declares, beside the live rules that
# forward them. A thin wrapper : it execs the engine proxmox_network.show_sdn.to.jsons.sh with
# --scope dc, and nothing else. The engine carries the context guard, the api fast path, the
# ansible slow path and the three outputs (--json, --text, --table).
#
# THIS IS THE GRAIN THAT SEES WHAT THE OTHERS CANNOT : an apply is an ifreload, which replays the
# post-up hook of every active subnet, so a gesture on one network adds a rule to all the others.
# Here every count is on the same screen. And it is the only grain that reports the live rules
# whose source network no subnet declares (level rules_only) : an egress the sdn does not account
# for, a legacy stanza left behind, a network another scenario owns.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "    $(basename "$0") --table"
  echo "    $(basename "$0") --json | jq -c 'select((.snat_rules // 0) > 1)'      # networks an apply duplicated"
  echo "    $(basename "$0") --json | jq -c 'select(.snat_origin == \"mixed\")'     # two rule shapes, left alone by every gesture"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the declared sdn of EVERY network of the cluster, beside their live rules "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help]"
  echo "  $(basename "$0") [--json|--text|--table]"
  echo
  echo "  same lines and same outputs as proxmox_network.show_sdn.to.jsons.sh (see its --help), scope fixed to dc"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

exec proxmox_network.show_sdn.to.jsons.sh --scope dc "$@"
