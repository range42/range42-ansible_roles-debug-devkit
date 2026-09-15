#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox_firewall.proxmox_node.enable_management_access_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_firewall.proxmox_node.enable_management_access.to.jsons.sh
#
# The anti-lockout of the node, the same steps as the role action
# firewall_node_enable_management_access, field for field :
#   1. GET  ${API_URL}/nodes/${NODE}/firewall/rules   read before write : an accept counts as "already
#      in place" only when ACTIVE and ABOVE the first deny that covers its port
#   2. POST the api accept (8006) then the ssh accept (22), active, at the requested
#      positions (0 and 1 : nothing can sit above them), each only when not already in place
#   3. GET  the chain back, and REFUSE to report a chain that grants nothing : the api
#      ignores the position asked for and inserts at the top, so posting is not knowing
#
# OUTPUT : one line per rule, `node_fw_rule` says which ("api" or "ssh"). Read the `_before`
# and `_after` fields to know the state, never the `_requested` one. 99999 : no deny at all.
#
# Optional fields, as in the role : node_fw_api_port (8006), node_fw_ssh_port (22), node_fw_api_pos (0),
# node_fw_ssh_pos (1), node_fw_mgmt_source (none : accepted from anywhere), node_fw_api_comment,
# node_fw_ssh_comment. The node comes from the vault ; a different proxmox_node on stdin is
# ignored with a trace.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="firewall_node_enable_management_access"
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
  echo "    echo '{\"proxmox_node\":\"px-testing\",\"node_fw_mgmt_source\":\"192.168.0.0/16\"}' | $(basename "$0")"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Install the two rules that keep the node reachable - direct Proxmox HTTPS API call ($ACTION)"
  echo
  echo OPTIONS
  echo
  echo "                                       $(basename "$0") [-h|--help]"
  echo "  STDIN :: [proxmox_node|JSON_LINE] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [proxmox_node|JSON_LINE] | $(basename "$0") [--text]    - force output as text"
  echo
  echo OPTIONAL FIELDS
  echo
  echo "  node_fw_api_port      the api port to accept, 8006 when omitted"
  echo "  node_fw_ssh_port      the ssh port to accept, 22 when omitted"
  echo "  node_fw_api_pos       where to post the api accept, 0 when omitted"
  echo "  node_fw_ssh_pos       where to post the ssh accept, 1 when omitted"
  echo "  node_fw_mgmt_source   restrict both accepts to a source, unrestricted when omitted"
  echo "  node_fw_api_comment   comment on the api rule"
  echo "  node_fw_ssh_comment   comment on the ssh rule"
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
  API_POS="$(printf '%s' "$REQ" | jq -r '.node_fw_api_pos // 0 | tostring')"
  SSH_POS="$(printf '%s' "$REQ" | jq -r '.node_fw_ssh_pos // 1 | tostring')"
  [[ "$API_POS" =~ ^[0-9]+$ ]] || API_POS=0
  [[ "$SSH_POS" =~ ^[0-9]+$ ]] || SSH_POS=1
  MGMT_SOURCE="$(printf '%s' "$REQ" | jq -r '.node_fw_mgmt_source // empty')"
  API_COMMENT="$(printf '%s' "$REQ" | jq -r '.node_fw_api_comment // "range42 anti-lockout, proxmox api"')"
  SSH_COMMENT="$(printf '%s' "$REQ" | jq -r '.node_fw_ssh_comment // "range42 anti-lockout, ssh"')"

  # 1. read before write
  _api_get "${API_URL}/nodes/${NODE}/firewall/rules"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "cannot read the node firewall rules (http ${HTTP_CODE}) : nothing was changed. ${BODY}"
    exit 1
  fi
  BEFORE="$(printf '%s' "$BODY" | fw_chain_verdict "$API_PORT" "$SSH_PORT")"
  HAS_API="$(printf '%s' "$BEFORE" | jq -r '.has_api')"
  HAS_SSH="$(printf '%s' "$BEFORE" | jq -r '.has_ssh')"
  _trace "$(printf '%s' "$BEFORE" | jq -r --arg a "$API_PORT" --arg s "$SSH_PORT" '"first covering deny, api at " + (.cover_api | tostring) + " and ssh at " + (.cover_ssh | tostring) + " : api " + $a + " at " + (.api_first | tostring) + " -> " + (if .has_api then "protected" else "NOT PROTECTED, will be posted" end) + " ; ssh " + $s + " at " + (.ssh_first | tostring) + " -> " + (if .has_ssh then "protected" else "NOT PROTECTED, will be posted" end)')"

  _post_accept() {
    local dport="$1" pos="$2" comment="$3" rule
    rule="$(jq -nc --arg p "$dport" --argjson pos "$pos" --arg src "$MGMT_SOURCE" --arg comment "$comment" '
      {
        type: "in",
        action: "ACCEPT",
        proto: "tcp",
        dport: $p,
        enable: 1,
        pos: $pos,
        source: (if ($src | length) > 0 then $src else null end),
        comment: $comment
      }
      | with_entries(select(.value != null))
    ')"
    _api_post "${API_URL}/nodes/${NODE}/firewall/rules" "$rule"
    if [[ "$HTTP_CODE" != "200" ]]; then
      _error "POST the accept on port ${dport} failed at the node (http ${HTTP_CODE}) : ${BODY}"
      exit 1
    fi
  }

  # 2. the api port first : it is the way back in if anything else goes wrong ; then ssh
  [[ "$HAS_API" == "true" ]] || _post_accept "$API_PORT" "$API_POS" "$API_COMMENT"
  [[ "$HAS_SSH" == "true" ]] || _post_accept "$SSH_PORT" "$SSH_POS" "$SSH_COMMENT"

  # 3. read back, then refuse to report a chain that grants nothing
  _api_get "${API_URL}/nodes/${NODE}/firewall/rules"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "the rules may have been posted but the chain could not be read back (http ${HTTP_CODE}) : ${BODY}"
    exit 1
  fi
  AFTER="$(printf '%s' "$BODY" | fw_chain_verdict "$API_PORT" "$SSH_PORT")"
  if [[ "$(printf '%s' "$AFTER" | jq -r '.has_api and .has_ssh')" != "true" ]]; then
    _error "$(printf '%s' "$AFTER" | jq -r --arg a "$API_PORT" --arg s "$SSH_PORT" '
      "The rules were written but the way back in is NOT in place, so this action will not report success. What the chain holds now : the web interface port " + $a + " "
      + (if .api_first >= 99999 then "is not accepted by any active rule" else "is accepted at position " + (.api_first | tostring) end) + " ; SSH " + $s + " "
      + (if .ssh_first >= 99999 then "is not accepted by any active rule" else "is accepted at position " + (.ssh_first | tostring) end)
      + ". A rule that exists but is disabled does not count as accepted, and an accept placed below a rule that blocks the same port never runs. Read the chain, remove what is in the way, and run this action again. Turning the firewall on as it stands would cut remote access, and the arming action will refuse it."
    ')"
    exit 1
  fi
  _trace "$(printf '%s' "$AFTER" | jq -r '"way back in confirmed : api accepted at position " + (.api_first | tostring) + ", ssh at " + (.ssh_first | tostring) + ", first covering deny at " + (if .cover_api >= 99999 then "none" else (.cover_api | tostring) end) + " for the api and " + (if .cover_ssh >= 99999 then "none" else (.cover_ssh | tostring) end) + " for ssh"')"

  for rule in api ssh ; do
    if [[ "$rule" == "api" ]]; then dport="$API_PORT" ; pos_req="$API_POS" ; else dport="$SSH_PORT" ; pos_req="$SSH_POS" ; fi
    jq -nc \
      --arg action "$ACTION" \
      --arg source "$SOURCE_TAG" \
      --arg node "$NODE" \
      --arg rule "$rule" \
      --arg dport "$dport" \
      --argjson pos_requested "$pos_req" \
      --argjson before "$BEFORE" \
      --argjson after "$AFTER" \
      --arg src "$MGMT_SOURCE" \
      '{
        action: $action,
        source: $source,
        proxmox_node: $node,
        node_fw_rule: $rule,
        node_fw_dport: $dport,
        node_fw_pos_requested: $pos_requested,
        node_fw_pos_before: (if $rule == "api" then $before.api_first else $before.ssh_first end),
        node_fw_pos_after: (if $rule == "api" then $after.api_first else $after.ssh_first end),
        node_fw_already_present: (if $rule == "api" then $before.has_api else $before.has_ssh end),
        node_fw_covering_deny_pos_before: (if $rule == "api" then $before.cover_api else $before.cover_ssh end),
        node_fw_mgmt_source: (if ($src | length) > 0 then $src else null end)
      }
      | with_entries(select(.value != null))' | _emit
  done
done
