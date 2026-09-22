#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox_firewall.vm_id.disable_firewall_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_firewall.vm_id.disable_firewall.to.jsons.sh
#
# The same steps as the role action firewall_vm_disable, field for field :
#   1. GET .../qemu/<vm_id>/firewall/rules    the chain, to SAY how many active rules are
#      about to stop applying : turning a firewall off locks nobody out, it removes
#      protection, and that count must not look like turning off nothing
#   2. PUT .../qemu/<vm_id>/firewall/options  enable 0
#
# Reads json lines or plain vm_ids on stdin. The vm_name comes from the api, as the facade
# resolves it before the ansible path.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="firewall_vm_disable"
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
  echo "  $(basename "$0") - Disable vm firewall, saying what becomes inert - direct Proxmox HTTPS API call ($ACTION)"
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

  _api_get "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/status/current"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "cannot read vm ${VM_ID} on node ${NODE} (http ${HTTP_CODE}) : nothing was changed. ${BODY}"
    exit 1
  fi
  VM_NAME="$(printf '%s' "$BODY" | jq -r '.data.name // ""')"

  # 1. the chain : what is about to become inert
  _api_get "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/firewall/rules"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "cannot read the firewall rules of vm ${VM_ID} (http ${HTTP_CODE}) : nothing was changed. ${BODY}"
    exit 1
  fi
  VERDICT="$(printf '%s' "$BODY" | fw_chain_verdict 8006 22)"
  _trace "$(printf '%s' "$VERDICT" | jq -r '"TURNING OFF the vm firewall : " + (.total | tostring) + " rule(s) in the chain, " + (.active | tostring) + " of them ACTIVE and about to stop applying. This is not a refusal, it is the count, so that turning off a whole policy does not look like turning off nothing."')"

  # 2. the write
  _api_put "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/firewall/options" '{"enable":0}'
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "PUT firewall/options enable=0 failed for vm ${VM_ID} (http ${HTTP_CODE}) : ${BODY}"
    exit 1
  fi

  jq -nc \
    --arg action "$ACTION" \
    --arg source "$SOURCE_TAG" \
    --arg node "$NODE" \
    --argjson vm_id "$VM_ID" \
    --arg vm_name "$VM_NAME" \
    '{
      action: $action,
      source: $source,
      proxmox_node: $node,
      vm_id: $vm_id,
      vm_name: $vm_name,
      vm_firewall: "disabled"
    }' | _emit
done
