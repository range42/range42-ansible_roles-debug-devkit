#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# delete a complete SDN network : subnet -> vnet -> zone + apply + reconcile.
#
# A thin wrapper : the whole sequence lives in proxmox__inc.sdn_network.to.jsons.sh so
# that create and delete cannot drift apart. The order is imposed by Proxmox, a vnet
# still holding a subnet cannot go, nor a zone still holding a vnet.
#
# IDEMPOTENT BY LOOKUP, NOT BY TOLERANCE
# Proxmox answers HTTP 500 "does not exist" on a delete of something absent. Rather than
# tolerate that 500, which would mean matching an error string and would also swallow the
# real failures, each object is looked up first. Absent means nothing to do, and it is
# REPORTED as skipped in the summary. So this runs on an empty cluster and says so.
#
# The apply and the want=0 reconciliation run even when everything was skipped : the
# first converges the running config, the second proves no SNAT rule outlived its
# declaration. Both are cheap and both are the only evidence of the end state.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "  :: TAKE DOWN THE NETWORK CREATED BY create_sdn_network"
  echo
  echo "    echo '{\"proxmox_node\":\"px-testing\",\"sdn_zone\":\"r42test\",\"sdn_vnet\":\"net199\",\"sdn_subnet\":\"192.168.199.0/24\"}' \\"
  echo "      | $(basename "$0")"
  echo
  echo "  :: SAFE TO REPLAY - a second run reports every step as skipped"
  echo
  echo "    ... | $(basename "$0") | jq -c '{steps_ok, steps_skipped}'"
  echo
  echo "  :: WHAT IS LEFT AFTERWARDS, TO CHECK BY HAND"
  echo
  echo "    proxmox_network.datacenter.list_sdn_zones.to.jsons.sh   | jq -c"
  echo "    proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh | jq -c"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - delete a complete SDN network, apply, reconcile the live rules"
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  STDIN :: [JSON] | $(basename "$0")"
  echo
  echo "  required : proxmox_node, sdn_zone, sdn_vnet, sdn_subnet (CIDR)"
  echo
  echo "  the CIDR is needed twice : to derive the subnet id Proxmox built"
  echo "  (<zone>-<network>-<mask>) and to anchor the rule reconciliation"
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

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh \
  "STR::sdn_zone" "STR::sdn_vnet" "STR::sdn_subnet" "STR::proxmox_node" "STR::action")

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"

  NODE=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.proxmox_node // empty')
  ZONE=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.sdn_zone // empty')
  VNET=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.sdn_vnet // empty')
  CIDR=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.sdn_subnet // empty')

  proxmox__inc.sdn_network.to.jsons.sh delete "$NODE" "$ZONE" "$VNET" "$CIDR"

done
