#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox_firewall.vm_id.enable_firewall_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_firewall.vm_id.enable_firewall.to.jsons.sh
#
# The same guard and the same write as the role action firewall_vm_enable, field for field :
#   1. GET  .../qemu/<vm_id>/firewall/rules   the chain, read fresh
#   2. REFUSE to arm a guest whose ssh port is not accepted by an active rule sitting ABOVE
#      the first deny that covers it : a firewall enabled with no accepted path is a deny,
#      and a guest nobody can reach is a guest nobody can operate
#   3. GET  /cluster/firewall/options          WARN, never refuse, when the datacenter switch
#      is off : this arming then filters nothing, and arming the datacenter later activates
#      every armed guest chain at once
#   4. PUT  .../qemu/<vm_id>/firewall/options  enable 1
#
# Reads json lines or plain vm_ids on stdin. Optional : vm_fw_ssh_port (22). The vm_name
# comes from the api, as the facade resolves it before the ansible path.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="firewall_vm_enable"
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
  echo "    proxmox_vm.list_with_api.to.jsons.sh | jq -r '.vm_id' | $(basename "$0")"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Enable vm firewall, refusing a guest with no ssh - direct Proxmox HTTPS API call ($ACTION)"
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

  # the name, as the facade resolves it before calling the ansible path
  _api_get "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/status/current"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "cannot read vm ${VM_ID} on node ${NODE} (http ${HTTP_CODE}) : nothing was changed. ${BODY}"
    exit 1
  fi
  VM_NAME="$(printf '%s' "$BODY" | jq -r '.data.name // ""')"

  # 1. the chain, read fresh
  _api_get "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/firewall/rules"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "cannot read the firewall rules of vm ${VM_ID} (http ${HTTP_CODE}) : nothing was changed. ${BODY}"
    exit 1
  fi
  VERDICT="$(printf '%s' "$BODY" | fw_chain_verdict 8006 "$SSH_PORT")"

  # 2. refuse to arm a guest with no ssh
  if [[ "$(printf '%s' "$VERDICT" | jq -r '.has_ssh')" != "true" ]]; then
    _error "$(printf '%s' "$VERDICT" | jq -r --arg p "$SSH_PORT" '
      "Refused. Turning the firewall on for this guest would drop all inbound traffic to it, SSH on port " + $p + " included. A guest may be cut off from the internet, from other guests and from students, but never from the machines that administer it : recovering it would need the console. What its rule chain says right now : SSH "
      + (if .ssh_first >= 99999 then "is not accepted by any active rule"
         else "is accepted at position " + (.ssh_first | tostring) + ", but a blocking rule sits above it at position " + (.cover_ssh | tostring) + ", so that accept never runs" end)
      + " ; and "
      + (if .cover_ssh >= 99999 then "no rule blocks inbound traffic explicitly, but with no accepted path the default policy drops it anyway"
         else "the first rule that blocks inbound traffic is at position " + (.cover_ssh | tostring) end)
      + ". A rule that exists but is disabled does not count as accepted. To fix this, add the default SSH rules first with proxmox_firewall.vm_id.enable_default_ssh_rules.to.jsons.sh (role action firewall_vm_enable_default_ssh_rules), then run this one again."
    ')"
    exit 1
  fi
  _trace "$(printf '%s' "$VERDICT" | jq -r --arg p "$SSH_PORT" '"ssh reachable on " + $p + " at position " + (.ssh_first | tostring) + ", first deny covering ssh at " + (.cover_ssh | tostring) + " : arming the guest firewall"')"

  # 3. the datacenter switch : a warning, never a refusal
  _api_get "${API_URL}/cluster/firewall/options"
  DC_SWITCH="0"
  [[ "$HTTP_CODE" == "200" ]] && DC_SWITCH="$(printf '%s' "$BODY" | jq -r '(.data.enable // 0) | tostring' 2>/dev/null || echo 0)"
  if [[ "$DC_SWITCH" == "0" ]]; then
    _trace "WARNING. The datacenter firewall switch is OFF, so arming this guest filters NOTHING. Its rules will be listed, its switch will read 1, and no packet will be filtered by any of them. This action continues, because preparing a guest before the datacenter is armed is a legitimate order of operations. Until the datacenter is armed, this guest is NOT isolated ; and when it is armed, every guest chain already in place becomes active at the same instant."
  fi

  # 4. the write
  _api_put "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/firewall/options" '{"enable":1}'
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "PUT firewall/options enable=1 failed for vm ${VM_ID} (http ${HTTP_CODE}) : ${BODY}"
    exit 1
  fi

  jq -nc \
    --arg action "$ACTION" \
    --arg source "$SOURCE_TAG" \
    --arg node "$NODE" \
    --argjson vm_id "$VM_ID" \
    --arg vm_name "$VM_NAME" \
    --argjson verdict "$VERDICT" \
    '{
      action: $action,
      source: $source,
      proxmox_node: $node,
      vm_id: $vm_id,
      vm_name: $vm_name,
      vm_firewall: "enabled",
      rules_total_before: $verdict.total,
      rules_active_before: $verdict.active
    }' | _emit
done
