#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# flip outbound NAT for one subnet, whichever way it currently is.
#
# A thin wrapper : the whole sequence lives in proxmox__inc.sdn_outgoing_nat.to.jsons.sh
# so that enable, disable and toggle cannot drift apart. Turning NAT on or off is three
# calls, not one, and the third is the one that gets forgotten :
#
#     update_sdn_subnet  ->  apply_sdn  ->  delete_snat_rules
#
# Only the subnet ID is needed. The vnet and the CIDR the other steps require are read
# from list_sdn_subnets, which also proves the subnet exists before anything is written.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
SDN_WANT="toggle"

show_example() {
  echo "  :: WITH THE SUBNET ID AS ARGUMENT"
  echo
  echo "    $(basename "$0") r42zone-192.168.199.0-24"
  echo
  echo "  :: LIST THE REAL IDS FIRST"
  echo
  echo "    proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh | jq -r '.subnet'"
  echo
  echo "  :: PIPING - every subnet of one vnet"
  echo
  echo "    proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh \\"
  echo "      | jq -r 'select(.subnet_vnet==\"net199\") | .subnet' \\"
  echo "      | while read -r s ; do $(basename "$0") \"\$s\" ; done"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ -z "${1:-}" ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - flip outbound NAT for one subnet, whichever way it currently is"
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  $(basename "$0") <sdn_subnet_id>"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.sdn_outgoing_nat.to.jsons.sh "$1" "$SDN_WANT"
