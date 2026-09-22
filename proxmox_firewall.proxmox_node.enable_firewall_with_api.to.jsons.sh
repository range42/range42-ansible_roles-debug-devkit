#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox_firewall.proxmox_node.enable_firewall_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_firewall.proxmox_node.enable_firewall.to.jsons.sh
#
# Arming a node with no accepted path to 8006 and 22 loses the web interface AND ssh on the
# machine this tooling talks to. The same guard as the role action firewall_node_enable,
# field for field :
#   1. GET .../nodes/<node>/firewall/rules  the node chain : where it starts denying, and
#      whether each management port is accepted ABOVE that, by an ACTIVE rule
#   2. GET /cluster/firewall/rules          the datacenter chain too : the node chain is
#      evaluated first and decides the ports it speaks about ; a port it says nothing about
#      is decided by the datacenter. A datacenter chain that cannot be read is NOT an empty
#      one : when the node is silent on a port and the datacenter is unreadable, REFUSE
#   3. PUT .../nodes/<node>/firewall/options  enable 1
#
# No escape hatch. Optional fields, as in the role : node_fw_api_port (8006),
# node_fw_ssh_port (22). The node comes from the vault, one node per workspace.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="firewall_node_enable"
SOURCE_TAG="proxmox-api"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text)"
  echo
  echo "    echo \"px-testing\" | $(basename "$0")"
  echo
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo
  echo "    echo '{\"proxmox_node\":\"px-testing\"}' | $(basename "$0") --json"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Enable the node firewall, refusing to do it blind - direct Proxmox HTTPS API call ($ACTION)"
  echo
  echo OPTIONS
  echo
  echo "                                       $(basename "$0") [-h|--help]"
  echo "  STDIN :: [proxmox_node|JSON_LINE] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [proxmox_node|JSON_LINE] | $(basename "$0") [--text]    - force output as text"
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
  echo "ERROR: no input on stdin. Pipe the node (plain text or JSON lines)." >&2
  show_example >&2
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# shared context guard : same refusals as the ansible path
proxmox__inc.warmup_checks.sh

# the api credentials of the active workspace, the request helpers, the chain predicates
source proxmox__inc.api_auth.sh
source proxmox__inc.firewall_chain.sh

_trace() { devkit_utils.text.echo_trace.to.text.to.stderr.sh "$@" ; }
_error() { devkit_utils.text.echo_error.to.text.to.stderr.sh "$@" ; }
_emit()  { if [[ "$OUTPUT_JSON" == true ]]; then jq -c . ; else jq -r 'to_entries[] | "\(.key)=\(.value)"' ; fi ; }

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

while IFS= read -r LINE ; do
  [[ -z "$LINE" ]] && continue

  REQ="$(printf '%s' "$LINE" | jq -cR '(fromjson? // .) as $v | if ($v | type) == "object" then $v else {proxmox_node: $v} end' 2>/dev/null || echo '{}')"

  LINE_NODE="$(printf '%s' "$REQ" | jq -r '.proxmox_node // empty')"
  [[ -z "$LINE_NODE" || "$LINE_NODE" == "$NODE" ]] || _trace "proxmox_node ${LINE_NODE} given on stdin is ignored, the node comes from the vault : ${NODE}"

  API_PORT="$(printf '%s' "$REQ" | jq -r '.node_fw_api_port // "8006" | tostring')"
  SSH_PORT="$(printf '%s' "$REQ" | jq -r '.node_fw_ssh_port // "22" | tostring')"

  # 1. the node chain, read fresh
  _api_get "${API_URL}/nodes/${NODE}/firewall/rules"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "cannot read the firewall rules of node ${NODE} (http ${HTTP_CODE}) : nothing was changed. ${BODY}"
    exit 1
  fi
  NV="$(printf '%s' "$BODY" | fw_chain_verdict "$API_PORT" "$SSH_PORT")"

  # 2. the datacenter chain too, and whether it was readable at all
  _api_get "${API_URL}/cluster/firewall/rules"
  DC_READABLE=false
  DV='{"has_api":false,"has_ssh":false}'
  if [[ "$HTTP_CODE" == "200" ]]; then
    DC_READABLE=true
    DV="$(printf '%s' "$BODY" | fw_chain_verdict "$API_PORT" "$SSH_PORT")"
  fi

  # the node decides the ports it speaks about, the datacenter decides the rest
  VERDICT="$(jq -nc --argjson n "$NV" --argjson d "$DV" --argjson dc_readable "$DC_READABLE" '
    {
      node: $n,
      dc_readable: $dc_readable,
      has_api: (if ([$n.api_first, $n.cover_api] | min) < 99999 then ($n.api_first < $n.cover_api) elif $dc_readable then $d.has_api else false end),
      has_ssh: (if ([$n.ssh_first, $n.cover_ssh] | min) < 99999 then ($n.ssh_first < $n.cover_ssh) elif $dc_readable then $d.has_ssh else false end)
    }
  ')"

  if [[ "$(printf '%s' "$VERDICT" | jq -r '.has_api and .has_ssh')" != "true" ]]; then
    _error "$(printf '%s' "$VERDICT" | jq -r --arg node "$NODE" --arg a "$API_PORT" --arg s "$SSH_PORT" '
      (if .dc_readable then "" else "Refused. This node chain says nothing about the port(s) at stake, so the guard needed the DATACENTER chain to decide, and that chain could NOT be read. An unreadable chain is not an empty one : it is an absence of fact, and arming on it would be arming on an assumption. Check that the api token may read /cluster/firewall/rules, then run this again. " end)
      + "Refused. Turning the firewall on for node " + $node + " would drop all inbound traffic on it, including the Proxmox web interface on port " + $a + " and SSH on port " + $s + ". You would lose remote access to this node, and getting it back would need console access. What its rule chain says right now : the web interface port "
      + (if .node.api_first >= 99999 then "is not accepted by any active rule" elif .has_api then "is accepted at position " + (.node.api_first | tostring) else "is accepted at position " + (.node.api_first | tostring) + ", but a blocking rule sits above it at position " + (.node.cover_api | tostring) + ", so that accept never runs" end)
      + " ; SSH "
      + (if .node.ssh_first >= 99999 then "is not accepted by any active rule" elif .has_ssh then "is accepted at position " + (.node.ssh_first | tostring) else "is accepted at position " + (.node.ssh_first | tostring) + ", but a blocking rule sits above it at position " + (.node.cover_ssh | tostring) + ", so that accept never runs" end)
      + " ; and "
      + (if .node.cover_api >= 99999 then "no rule blocks inbound traffic explicitly, but with no accepted path the default policy drops it anyway" else "the first rule that blocks inbound traffic is at position " + (.node.cover_api | tostring) end)
      + ". A rule that exists but is disabled does not count as accepted. To fix this, add the accepted paths first with proxmox_firewall.proxmox_node.enable_management_access.to.jsons.sh (role action firewall_node_enable_management_access), then run this one again. If your accept is restricted to specific source addresses, this check does not verify that the caller is among them."
    ')"
    exit 1
  fi
  _trace "$(printf '%s' "$VERDICT" | jq -r --arg node "$NODE" '"way back in confirmed on " + $node + " : api at " + (.node.api_first | tostring) + ", ssh at " + (.node.ssh_first | tostring) + ", first covering deny : api " + (.node.cover_api | tostring) + ", ssh " + (.node.cover_ssh | tostring) + " : arming the node firewall"')"

  # 3. the write
  _api_put "${API_URL}/nodes/${NODE}/firewall/options" '{"enable":1}'
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "PUT node firewall/options enable=1 failed for ${NODE} (http ${HTTP_CODE}) : ${BODY}"
    exit 1
  fi

  jq -nc \
    --arg action "$ACTION" \
    --arg source "$SOURCE_TAG" \
    --arg node "$NODE" \
    '{
      action: $action,
      source: $source,
      proxmox_node: $node,
      node_firewall: "enabled"
    }' | _emit
done
