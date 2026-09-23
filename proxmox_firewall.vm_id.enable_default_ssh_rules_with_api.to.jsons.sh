#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox_firewall.vm_id.enable_default_ssh_rules_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_firewall.vm_id.enable_default_ssh_rules.to.jsons.sh
#
# The same steps as the role action firewall_vm_enable_default_ssh_rules, field for field :
#   1. GET  .../qemu/<vm_id>/firewall/rules   read before write : an accept on the ssh port
#      counts as "already in place" only when ACTIVE and ABOVE the first deny that covers it
#   2. POST .../qemu/<vm_id>/firewall/rules   the accept, active, at the requested position
#      (0 by default : nothing can sit above it), only when it is not already in place. No
#      deny is posted : PVE ends every guest chain with a drop of its own
#   3. GET  the chain back, and REFUSE to report a chain that grants nothing
#
# OUTPUT : one line per rule this action manages, `vm_fw_rule` says which ("ssh_accept").
# `vm_fw_already_present` is the one to select on.
#
# Optional fields, as in the role : vm_fw_ssh_accept_pos (0), vm_fw_mgmt_source (none :
# accepted from anywhere), vm_fw_ssh_accept_comment, vm_fw_ssh_port (22 ; the role hard
# codes 22 for the accept it looks for and takes the parameter for the deny it excludes,
# this twin takes the parameter for both, identical at the default).
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="firewall_vm_enable_default_ssh_rules"
SOURCE_TAG="proxmox-api"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text)"
  echo
  echo "    echo \"100\" | $(basename "$0")"
  echo
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo
  echo "    echo '{\"vm_id\":100}' | $(basename "$0") --json"
  echo "    echo '{\"vm_id\":100,\"vm_fw_mgmt_source\":\"192.168.0.0/16\"}' | $(basename "$0")"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Install the default ssh rule set on one guest - direct Proxmox HTTPS API call ($ACTION)"
  echo
  echo OPTIONS
  echo
  echo "                                $(basename "$0") [-h|--help]"
  echo "  STDIN :: [VM_ID|JSON_LINE] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [VM_ID|JSON_LINE] | $(basename "$0") [--text]    - force output as text"
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
  echo "ERROR: no input on stdin. Pipe vm_id(s) (plain text or JSON lines)." >&2
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

  REQ="$(printf '%s' "$LINE" | jq -cR '(fromjson? // .) as $v | if ($v | type) == "object" then $v else {vm_id: $v} end' 2>/dev/null || echo '{}')"

  LINE_NODE="$(printf '%s' "$REQ" | jq -r '.proxmox_node // empty')"
  [[ -z "$LINE_NODE" || "$LINE_NODE" == "$NODE" ]] || _trace "proxmox_node ${LINE_NODE} given on stdin is ignored, the node comes from the vault : ${NODE}"

  VM_ID="$(printf '%s' "$REQ" | jq -r '.vm_id // empty | tostring')"
  if ! [[ "$VM_ID" =~ ^[0-9]+$ ]]; then
    _error "cannot extract an integer vm_id from : $LINE"
    exit 1
  fi
  SSH_PORT="$(printf '%s' "$REQ" | jq -r '.vm_fw_ssh_port // "22" | tostring')"
  POS_REQ="$(printf '%s' "$REQ" | jq -r '.vm_fw_ssh_accept_pos // 0 | tostring')"
  [[ "$POS_REQ" =~ ^[0-9]+$ ]] || POS_REQ=0
  MGMT_SOURCE="$(printf '%s' "$REQ" | jq -r '.vm_fw_mgmt_source // empty')"
  COMMENT="$(printf '%s' "$REQ" | jq -r '.vm_fw_ssh_accept_comment // "range42 default ssh access"')"

  # 1. read before write
  _api_get "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/firewall/rules"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "cannot read the firewall rules of vm ${VM_ID} (http ${HTTP_CODE}) : nothing was changed. ${BODY}"
    exit 1
  fi
  BEFORE="$(printf '%s' "$BODY" | fw_chain_verdict 8006 "$SSH_PORT")"
  HAS_SSH="$(printf '%s' "$BEFORE" | jq -r '.has_ssh')"

  # 2. the accept, only when not already in place and well placed
  if [[ "$HAS_SSH" != "true" ]]; then
    RULE="$(jq -nc --arg p "$SSH_PORT" --argjson pos "$POS_REQ" --arg src "$MGMT_SOURCE" --arg comment "$COMMENT" '
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
    _api_post "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/firewall/rules" "$RULE"
    if [[ "$HTTP_CODE" != "200" ]]; then
      _error "POST the ssh accept failed for vm ${VM_ID} (http ${HTTP_CODE}) : ${BODY}"
      exit 1
    fi
  else
    _trace "ssh ${SSH_PORT} already accepted at position $(printf '%s' "$BEFORE" | jq -r '.ssh_first') and above the first covering deny : nothing posted"
  fi

  # 3. read back, then refuse to report a chain that grants nothing
  _api_get "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/firewall/rules"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "the rule may have been posted but the chain could not be read back (http ${HTTP_CODE}) : ${BODY}"
    exit 1
  fi
  AFTER="$(printf '%s' "$BODY" | fw_chain_verdict 8006 "$SSH_PORT")"
  if [[ "$(printf '%s' "$AFTER" | jq -r '.has_ssh')" != "true" ]]; then
    _error "$(printf '%s' "$AFTER" | jq -r --arg p "$SSH_PORT" '
      "The rules were written but the guest is NOT reachable on ssh, so this action will not report success. What the chain holds now : SSH " + $p + " "
      + (if .ssh_first >= 99999 then "is not accepted by any active rule" else "is accepted at position " + (.ssh_first | tostring) end) + " ; "
      + (if .cover_ssh >= 99999 then "no rule blocks inbound traffic" else "the first rule that blocks inbound traffic is at position " + (.cover_ssh | tostring) end)
      + ". An accept placed below a blocking rule never runs. Read the chain, remove what is in the way, and run this action again. Arming this guest as it stands would make it unreachable, and the arming action will refuse it."
    ')"
    exit 1
  fi

  jq -nc \
    --arg action "$ACTION" \
    --arg source "$SOURCE_TAG" \
    --arg node "$NODE" \
    --argjson vm_id "$VM_ID" \
    --arg dport "$SSH_PORT" \
    --argjson pos_requested "$POS_REQ" \
    --argjson after "$AFTER" \
    --argjson already "$HAS_SSH" \
    --arg src "$MGMT_SOURCE" \
    '{
      action: $action,
      source: $source,
      proxmox_node: $node,
      vm_id: $vm_id,
      vm_fw_rule: "ssh_accept",
      vm_fw_dport: $dport,
      vm_fw_pos_requested: $pos_requested,
      vm_fw_pos_after: $after.ssh_first,
      vm_fw_already_present: $already,
      vm_fw_mgmt_source: (if ($src | length) > 0 then $src else null end)
    }
    | with_entries(select(.value != null))' | _emit
done
