#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox_network.sdn_vnet.update_sdn_subnet_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_network.sdn_vnet.update_sdn_subnet.to.jsons.sh
#
# One PUT /cluster/sdn/vnets/<vnet>/subnets/<subnet_id> per json line, the same request and
# the same output fields as the role action network_update_sdn_subnet, source aside.
#
# >>> sdn_subnet_id IS THE ID, NOT THE CIDR <<<
# <zone>-<network>-<mask>, for instance r42zone-192.168.199.0-24 : anything with a slash is
# refused before anything is sent, as the role does. sdn_vnet and sdn_subnet_snat are
# required too : an update carrying no field would be a silent no-op.
#
# >>> THE TOGGLE IS THREE STEPS <<<
# this (the declaration), apply_sdn (it becomes live), delete_extra_snat_rules (the live
# rules are reconciled). Step 3 is not optional in either direction.
#
# A proxmox_node given on stdin is ignored with a trace : the node comes from the vault,
# one node per workspace, as every twin of this family does.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="network_update_sdn_subnet"
SOURCE_TAG="proxmox-api"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo
  echo "    echo '{\"sdn_vnet\":\"net199\",\"sdn_subnet_id\":\"r42zone-192.168.199.0-24\",\"sdn_subnet_snat\":1}' | $(basename "$0")"
  echo "    echo '{\"sdn_vnet\":\"net199\",\"sdn_subnet_id\":\"r42zone-192.168.199.0-24\",\"sdn_subnet_snat\":0}' | $(basename "$0") --text"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - update an SDN subnet, the snat toggle - direct Proxmox HTTPS API call ($ACTION)"
  echo
  echo OPTIONS
  echo
  echo "                             $(basename "$0") [-h|--help]"
  echo "  STDIN :: [JSON_LINE] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [JSON_LINE] | $(basename "$0") [--text]    - force output as text"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_JSON=true ; shift ;;
    --text) OUTPUT_JSON=false ; shift ;;
    *)
      echo "ERROR: unknown arg '$1'" >&2
      show_example >&2
      exit 1
      ;;
  esac
done

if [ -t 0 ]; then
  echo "ERROR: no input on stdin. Pipe json lines with sdn_vnet, sdn_subnet_id and sdn_subnet_snat." >&2
  show_example >&2
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# shared context guard : same refusals as the ansible path
proxmox__inc.warmup_checks.sh

# the api credentials of the active workspace, and the request helpers
source proxmox__inc.api_auth.sh

_trace() { devkit_utils.text.echo_trace.to.text.to.stderr.sh "$@" ; }
_error() { devkit_utils.text.echo_error.to.text.to.stderr.sh "$@" ; }
_emit()  { if [[ "$OUTPUT_JSON" == true ]]; then jq -c . ; else jq -r 'to_entries[] | "\(.key)=\(.value)"' ; fi ; }

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

while IFS= read -r LINE ; do
  [[ -z "$LINE" ]] && continue

  REQ="$(printf '%s' "$LINE" | jq -cR '(fromjson? // .) as $v | if ($v | type) == "object" then $v else {sdn_vnet: $v} end' 2>/dev/null || echo '{}')"

  LINE_NODE="$(printf '%s' "$REQ" | jq -r '.proxmox_node // empty')"
  [[ -z "$LINE_NODE" || "$LINE_NODE" == "$NODE" ]] || _trace "proxmox_node ${LINE_NODE} given on stdin is ignored, the node comes from the vault : ${NODE}"

  VNET="$(printf '%s' "$REQ" | jq -r '.sdn_vnet // empty | tostring')"
  SUBNET_ID="$(printf '%s' "$REQ" | jq -r '.sdn_subnet_id // empty | tostring')"
  SNAT="$(printf '%s' "$REQ" | jq -c '.sdn_subnet_snat // empty')"

  if [[ -z "$VNET" || -z "$SUBNET_ID" || -z "$SNAT" ]]; then
    _error "sdn_vnet, sdn_subnet_id and sdn_subnet_snat are all required, nothing was sent. Got : $LINE"
    exit 1
  fi
  if [[ "$SUBNET_ID" == *"/"* ]]; then
    _error "sdn_subnet_id must be the subnet ID as Proxmox built it, <zone>-<network>-<mask>, for instance r42zone-192.168.199.0-24. A CIDR is not accepted here : the read action returns the id in its subnet field and the network in subnet_cidr. Got: ${SUBNET_ID}"
    exit 1
  fi

  # the body : only the fields given travel, as the role does with default(omit)
  PUT_BODY="$(printf '%s' "$REQ" | jq -c '
    {
      snat: .sdn_subnet_snat,
      gateway: .sdn_subnet_gateway,
      "dhcp-range": .sdn_subnet_dhcp_range,
      "dhcp-dns-server": .sdn_subnet_dhcp_dns_server
    }
    | with_entries(select(.value != null))
  ')"

  _api_put "${API_URL}/cluster/sdn/vnets/${VNET}/subnets/${SUBNET_ID}" "$PUT_BODY"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "PUT subnet ${SUBNET_ID} of vnet ${VNET} failed (http ${HTTP_CODE}) : ${BODY}"
    exit 1
  fi

  # the same fields as the role : the cidr is rebuilt from the id, read from the right so a
  # zone name with dashes still parses, and left out rather than wrong when the id is short
  printf '%s' "$REQ" | jq -c \
    --arg action "$ACTION" \
    --arg source "$SOURCE_TAG" \
    --arg node "$NODE" \
    --arg subnet "$SUBNET_ID" \
    --arg vnet "$VNET" \
    '
      ($subnet | split("-")) as $p
      | {
          action: $action,
          source: $source,
          proxmox_node: $node,
          subnet: $subnet,
          subnet_vnet: $vnet,
          subnet_cidr: (if ($p | length) >= 3 then ($p[-2] + "/" + $p[-1]) else null end),
          subnet_snat: .sdn_subnet_snat,
          subnet_gateway: .sdn_subnet_gateway,
          subnet_dhcp_range: .sdn_subnet_dhcp_range,
          subnet_dhcp_dns_server: .sdn_subnet_dhcp_dns_server
        }
      | with_entries(select(.value != null))
    ' | _emit
done
