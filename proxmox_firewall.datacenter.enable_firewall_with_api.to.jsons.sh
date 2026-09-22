#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox_firewall.datacenter.enable_firewall_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_firewall.datacenter.enable_firewall.to.jsons.sh
#
# The most dangerous switch of the three : the datacenter rules apply to every node's host
# chain, so arming here with no accepted path loses the web interface AND ssh on EVERY
# node at once. The same guard as the role action firewall_dc_enable, field for field :
#   1. GET /cluster/firewall/rules       where the chain starts denying, and whether the
#      api port and the ssh port are accepted ABOVE that, by an ACTIVE rule
#   2. GET /nodes, then per node GET .../firewall/options and .../firewall/rules : the
#      datacenter chain does not decide alone. Node rules are evaluated BEFORE datacenter
#      rules in one host chain, first match wins, so an ARMED node whose chain shadows a
#      management accept beats the accept. A node that cannot be read cannot be cleared,
#      and an empty node list is never a real answer : both REFUSE
#   3. two refusals, because one message would lie : a node shadows (the datacenter chain
#      is sane, fix THE NODE), or the datacenter chain has no way back in (fix IT)
#   4. PUT /cluster/firewall/options     enable 1
#
# No escape hatch : a flag that skips a lockout guard is how lockout guards die.
# Optional fields, as in the role : dc_fw_api_port (8006), dc_fw_ssh_port (22).
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="firewall_dc_enable"
SOURCE_TAG="proxmox-api"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text : anything, the node comes from the vault)"
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
  echo "  $(basename "$0") - Enable the datacenter firewall, refusing to do it blind - direct Proxmox HTTPS API call ($ACTION)"
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

  API_PORT="$(printf '%s' "$REQ" | jq -r '.dc_fw_api_port // "8006" | tostring')"
  SSH_PORT="$(printf '%s' "$REQ" | jq -r '.dc_fw_ssh_port // "22" | tostring')"

  # 1. the datacenter chain, read fresh
  _api_get "${API_URL}/cluster/firewall/rules"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "cannot read the datacenter firewall rules (http ${HTTP_CODE}) : nothing was changed. ${BODY}"
    exit 1
  fi
  DC="$(printf '%s' "$BODY" | fw_chain_verdict "$API_PORT" "$SSH_PORT")"

  # 2. the nodes : listed, online, readable, and none of the armed ones shadowing an accept
  _api_get "${API_URL}/nodes"
  NODES_LISTED=false
  NODES_BODY='{"data":[]}'
  if [[ "$HTTP_CODE" == "200" ]] && [[ "$(printf '%s' "$BODY" | jq -r '(.data // []) | length' 2>/dev/null || echo 0)" -gt 0 ]]; then
    NODES_LISTED=true
    NODES_BODY="$BODY"
  fi
  OFFLINE="$(printf '%s' "$NODES_BODY" | jq -c '[.data[]? | select(has("status") and .status != "online") | .node]')"
  SHADOWING='[]'
  UNREADABLE='[]'
  while IFS= read -r n ; do
    [[ -z "$n" ]] && continue
    readable=true
    armed=false
    _api_get "${API_URL}/nodes/${n}/firewall/options"
    if [[ "$HTTP_CODE" == "200" ]]; then
      [[ "$(printf '%s' "$BODY" | jq -r '((.data // {}).enable // 0) | tostring')" != "0" ]] && armed=true
    else
      readable=false
    fi
    _api_get "${API_URL}/nodes/${n}/firewall/rules"
    if [[ "$HTTP_CODE" == "200" ]]; then
      NV="$(printf '%s' "$BODY" | fw_chain_verdict "$API_PORT" "$SSH_PORT")"
      shadows="$(printf '%s' "$NV" | jq -r '((.cover_api < 99999) and (.api_first >= .cover_api)) or ((.cover_ssh < 99999) and (.ssh_first >= .cover_ssh))')"
      if [[ "$armed" == true && "$shadows" == "true" ]]; then
        SHADOWING="$(printf '%s' "$SHADOWING" | jq -c --arg n "$n" '. + [$n]')"
      fi
    else
      readable=false
    fi
    [[ "$readable" == true ]] || UNREADABLE="$(printf '%s' "$UNREADABLE" | jq -c --arg n "$n" '. + [$n]')"
  done < <(printf '%s' "$NODES_BODY" | jq -r '.data[]? | .node // empty')

  VERDICT="$(jq -nc --argjson dc "$DC" --argjson listed "$NODES_LISTED" --argjson offline "$OFFLINE" --argjson unreadable "$UNREADABLE" --argjson shadowing "$SHADOWING" '
    {
      dc: $dc,
      nodes_listed: $listed,
      offline: $offline,
      unreadable: $unreadable,
      shadowing: $shadowing,
      dc_chain_grants: ($dc.has_api and $dc.has_ssh),
      all_nodes_read: ($listed and (($offline | length) == 0) and (($unreadable | length) == 0)),
      has_api: ($dc.has_api and (($shadowing | length) == 0)),
      has_ssh: ($dc.has_ssh and (($shadowing | length) == 0))
    }
  ')"

  # 3a. refuse to arm a cluster a node would shadow : the datacenter chain is NOT the problem
  if [[ "$(printf '%s' "$VERDICT" | jq -r '.dc_chain_grants and ((.shadowing | length) > 0)')" == "true" ]]; then
    _error "$(printf '%s' "$VERDICT" | jq -r '"Refused. The datacenter chain grants both ports, so it is NOT what blocks this arming. One or more ARMED node(s) of this cluster carry a chain that shadows a management accept : " + (.shadowing | join(", ")) + ". Node rules are emitted BEFORE datacenter rules in a single host chain and the first match wins, so a deny on a node beats an accept at the datacenter. Arming the datacenter would activate that deny and drop the port on that node, and the datacenter accept would never be reached. Fix the node chain with proxmox_firewall.proxmox_node.enable_management_access.to.jsons.sh (role action firewall_node_enable_management_access), or disarm that node, then run this one again."')"
    exit 1
  fi

  # 3b. refuse to arm a cluster with no way back in
  if [[ "$(printf '%s' "$VERDICT" | jq -r '.all_nodes_read and .has_api and .has_ssh')" != "true" ]]; then
    _error "$(printf '%s' "$VERDICT" | jq -r --arg a "$API_PORT" --arg s "$SSH_PORT" '
      (if .nodes_listed then "" else "Refused. The list of cluster nodes could not be obtained, so the guard does not know which nodes exist and cannot clear any of them. A cluster always holds at least the node answering this call, so an empty list is a symptom and not a fact. Check the api token and the cluster state, then run this again. " end)
      + (if .all_nodes_read or (.nodes_listed | not) then "" else
          "Refused. This cluster has node(s) whose firewall chain could NOT be read, so the guard cannot clear them : "
          + (if (.offline | length) > 0 then "not online : " + (.offline | join(", ")) + ". " else "" end)
          + (if (.unreadable | length) > 0 then "online but unreadable : " + (.unreadable | join(", ")) + ". " else "" end)
          + "A chain that cannot be read may hold a deny that shadows the management accepts, and nothing here can prove it does not. Bring the node back, or take it out of the cluster, then run this again. " end)
      + "Refused. Turning the datacenter firewall on would drop all inbound traffic on EVERY node of the cluster, not one, including the Proxmox web interface on port " + $a + " and SSH on port " + $s + ". You would lose remote access to all of them at once, and getting it back would need console access on each. What the datacenter rule chain says right now : the web interface port "
      + (if .dc.api_first >= 99999 then "is not accepted by any active rule" elif .dc.cover_api >= 99999 then "is accepted at position " + (.dc.api_first | tostring) + " and nothing at THIS level blocks it" else "is accepted at position " + (.dc.api_first | tostring) + ", but a blocking rule sits above it at position " + (.dc.cover_api | tostring) + ", so that accept never runs" end)
      + " ; SSH "
      + (if .dc.ssh_first >= 99999 then "is not accepted by any active rule" elif .dc.cover_ssh >= 99999 then "is accepted at position " + (.dc.ssh_first | tostring) + " and nothing at THIS level blocks it" else "is accepted at position " + (.dc.ssh_first | tostring) + ", but a blocking rule sits above it at position " + (.dc.cover_ssh | tostring) + ", so that accept never runs" end)
      + " ; and "
      + (if .dc.cover_api >= 99999 then "no rule blocks inbound traffic explicitly, but with no accepted path the default policy drops it anyway" else "the first rule that blocks inbound traffic is at position " + (.dc.cover_api | tostring) end)
      + ". A rule that exists but is disabled does not count as accepted. To fix this, add the accepted paths first with proxmox_firewall.datacenter.enable_management_access.to.jsons.sh (role action firewall_dc_enable_management_access), then run this one again. If your accept is restricted to specific source addresses, this check does not verify that the caller is among them."
    ')"
    exit 1
  fi
  _trace "$(printf '%s' "$VERDICT" | jq -r '"way back in confirmed at the datacenter : api at " + (.dc.api_first | tostring) + ", ssh at " + (.dc.ssh_first | tostring) + ", first deny at " + (.dc.cover_api | tostring) + ", no armed node shadows the management accepts : arming the datacenter firewall"')"

  # 4. the write
  _api_put "${API_URL}/cluster/firewall/options" '{"enable":1}'
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "PUT datacenter firewall/options enable=1 failed (http ${HTTP_CODE}) : ${BODY}"
    exit 1
  fi

  jq -nc \
    --arg action "$ACTION" \
    --arg source "$SOURCE_TAG" \
    --arg node "$NODE" \
    --argjson dc "$DC" \
    '{
      action: $action,
      source: $source,
      proxmox_node: $node,
      dc_firewall: "enabled",
      api_pos_before: $dc.api_first,
      ssh_pos_before: $dc.ssh_first,
      first_deny_pos_before: $dc.cover_api
    }' | _emit
done
