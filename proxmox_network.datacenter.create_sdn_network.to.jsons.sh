#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# create a complete, usable SDN network : zone + vnet + subnet + apply + reconcile.
#
# A thin wrapper : the whole sequence lives in proxmox__inc.sdn_network.to.jsons.sh so
# that create and delete cannot drift apart.
#
# Each object is looked up before being written, so a second run is a clean no-op and
# reports its steps as skipped rather than failing on "already defined".
#
# The subnet id Proxmox derives (<zone>-<network>-<mask>) is computed for you and
# carried in the summary line, ready to be piped into the outgoing NAT switch.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "  :: MINIMAL - a subnet with outbound NAT and no gateway"
  echo
  echo "    echo '{\"proxmox_node\":\"px-testing\",\"sdn_zone\":\"r42test\",\"sdn_vnet\":\"net199\",\"sdn_subnet\":\"192.168.199.0/24\"}' \\"
  echo "      | $(basename "$0")"
  echo
  echo "  :: WITH A GATEWAY, AND NAT EXPLICITLY OFF"
  echo
  echo "    echo '{\"proxmox_node\":\"px-testing\",\"sdn_zone\":\"r42test\",\"sdn_vnet\":\"net199\",\"sdn_subnet\":\"192.168.199.0/24\",\"sdn_subnet_gateway\":\"192.168.199.1\",\"sdn_subnet_snat\":0}' \\"
  echo "      | $(basename "$0")"
  echo
  echo "  :: THEN ATTACH A VM TO IT"
  echo
  echo "    echo '{\"proxmox_node\":\"px-testing\",\"vm_id\":102,\"iface_model\":\"virtio\",\"iface_bridge\":\"net199\"}' \\"
  echo "      | proxmox_network.vm_id.add_interfaces_vm.to.jsons.sh"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - create a complete SDN network, apply it, reconcile the live rules"
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  STDIN :: [JSON] | $(basename "$0")"
  echo
  echo "  required : proxmox_node, sdn_zone, sdn_vnet, sdn_subnet (CIDR)"
  echo "  optional : sdn_subnet_gateway, sdn_subnet_snat (default 1)"
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
#
# Every key below is REQUIRED. The two optional ones are read straight from the line,
# with their default applied here rather than deeper down, so the value that is used is
# the value that gets traced.
#
JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh \
  "STR::sdn_zone" "STR::sdn_vnet" "STR::sdn_subnet" "STR::proxmox_node" "STR::action")

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"

  NODE=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.proxmox_node // empty')
  ZONE=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.sdn_zone // empty')
  VNET=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.sdn_vnet // empty')
  CIDR=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.sdn_subnet // empty')
  GW=$(printf   '%s' "$CURRENT_JSON_LINE" | jq -r '.sdn_subnet_gateway // empty')
  ## // empty would drop a legitimate 0, so the default is applied on null only.
  SNAT=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r 'if .sdn_subnet_snat == null then 1 else .sdn_subnet_snat end')

  ## < /dev/null : on est dans un "printf | while read", et l include ne lit pas
  ## stdin. Sans la redirection, ses propres sous-commandes heriteraient du pipe
  ## de la boucle et le videraient.
  proxmox__inc.sdn_network.to.jsons.sh create "$NODE" "$ZONE" "$VNET" "$CIDR" "$GW" "$SNAT" < /dev/null

done
