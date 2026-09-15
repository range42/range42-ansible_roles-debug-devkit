#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox_firewall.vm_id.disable_firewall_iface_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_firewall.vm_id.disable_firewall_iface.to.jsons.sh
#
# The same steps as the role action firewall_vm_iface_disable, field for field, on ONE
# network card of ONE guest (vm_vmnet_id is the N of netN, required, no default) :
#   1. GET  .../qemu/<vm_id>/config             the card string, raw ; REFUSE a card that is
#      not there, nothing is written blind
#   2. EDIT the string it read : any firewall key removed, firewall=0 appended, every other
#      character untouched (the MAC, the bridge, the tag, the mtu). Already firewall=0 :
#      nothing is written
#   3. POST .../qemu/<vm_id>/config             the edited net<N>
#   4. GET  the stored config AND the running one (?current=1, read again until it follows,
#      ten seconds at most : a hotplug is not instantaneous), then REFUSE to report a
#      success that is not one : the flag must read 0, the MAC must not have changed, no
#      key may be lost, and the running guest must agree (a deferred change filters still until the guest reboots, and still blocks MAC spoofing)
#
# The same flag carries PVE's MAC anti-spoof, and the two cannot be separated.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="firewall_vm_iface_disable"
SOURCE_TAG="proxmox-api"
DEFAULT_OUTPUT_JSON=true
WANT="0"
CURRENT_READ_RETRIES=10
CURRENT_READ_DELAY=1

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: vm_vmnet_id IS REQUIRED, so a bare vm_id is not enough"
  echo
  echo "    echo '{\"vm_id\":100,\"vm_vmnet_id\":0}' | $(basename "$0")"
  echo "    echo '{\"vm_id\":100,\"vm_vmnet_id\":0}' | $(basename "$0") --text"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Disable the firewall flag of ONE network card of a vm - direct Proxmox HTTPS API call ($ACTION)"
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
  echo "ERROR: no input on stdin. Pipe json lines with vm_id and vm_vmnet_id." >&2
  show_example >&2
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# shared context guard : same refusals as the ansible path
proxmox__inc.warmup_checks.sh

# the api credentials of the active workspace, the request helpers, the card edit
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
  VMNET_ID="$(printf '%s' "$REQ" | jq -r '.vm_vmnet_id // empty | tostring')"
  if ! [[ "$VM_ID" =~ ^[0-9]+$ ]]; then
    _error "cannot extract an integer vm_id from : $LINE"
    exit 1
  fi
  if ! [[ "$VMNET_ID" =~ ^[0-9]+$ ]]; then
    _error "vm_vmnet_id is required and must be the N of netN, there is no default : a vm with several cards would otherwise have the wrong one touched. Got : $LINE"
    exit 1
  fi
  KEY="net${VMNET_ID}"

  _api_get "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/status/current"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "cannot read vm ${VM_ID} on node ${NODE} (http ${HTTP_CODE}) : nothing was changed. ${BODY}"
    exit 1
  fi
  VM_NAME="$(printf '%s' "$BODY" | jq -r '.data.name // ""')"

  # 1. the card, raw
  _api_get "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/config"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "cannot read the config of vm ${VM_ID} (http ${HTTP_CODE}) : nothing was changed. ${BODY}"
    exit 1
  fi
  BEFORE="$(printf '%s' "$BODY" | jq -r --arg k "$KEY" '.data[$k] // ""')"
  if [[ -z "$BEFORE" ]]; then
    _error "vm ${VM_ID} has no card ${KEY}, or its configuration could not be read. NOTHING was changed. Cards it really has : $(printf '%s' "$BODY" | jq -c '[.data | to_entries[] | select(.key | test("^net[0-9]+$")) | .key]')"
    exit 1
  fi
  _trace "${KEY} reads : ${BEFORE}"

  # 2. the edit, on the string itself
  EDIT="$(fw_iface_edit "$BEFORE" "$WANT")"
  WANTED="$(printf '%s' "$EDIT" | jq -r '.wanted')"
  ALREADY="$(printf '%s' "$EDIT" | jq -r '.already')"

  # 3. the write, unless the card already carries the flag
  if [[ "$ALREADY" == "true" ]]; then
    _trace "${KEY} of vm ${VM_ID} already carries firewall=${WANT} : skipped, the card was not rewritten and its MAC is untouched."
  else
    _api_post "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/config" "$(jq -nc --arg k "$KEY" --arg v "$WANTED" '{($k): $v}')"
    if [[ "$HTTP_CODE" != "200" ]]; then
      _error "POST config ${KEY} failed for vm ${VM_ID} (http ${HTTP_CODE}) : ${BODY}"
      exit 1
    fi
  fi

  # 4. the read-back, twice
  _api_get "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/config"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "the card may have been rewritten but the stored config could not be read back (http ${HTTP_CODE}) : ${BODY}"
    exit 1
  fi
  AFTER="$(printf '%s' "$BODY" | jq -r --arg k "$KEY" '.data[$k] // ""')"
  # the running config follows the stored one through a hotplug that is not instantaneous : read it until it agrees, a
  # bounded number of times. The role passes the same check only because its tasks take seconds between the write and
  # the read ; read at once, a card still being replugged reads as deferred and a good write is refused.
  CURRENT=""
  attempt=0
  while (( attempt < CURRENT_READ_RETRIES )); do
    _api_get "${API_URL}/nodes/${NODE}/qemu/${VM_ID}/config?current=1"
    CURRENT=""
    [[ "$HTTP_CODE" == "200" ]] && CURRENT="$(printf '%s' "$BODY" | jq -r --arg k "$KEY" '.data[$k] // ""')"
    [[ -z "$CURRENT" || "$CURRENT" == *"firewall=${WANT}"* ]] && break
    sleep "$CURRENT_READ_DELAY"
    attempt=$((attempt + 1))
  done

  VERDICT="$(fw_iface_verdict "$BEFORE" "$AFTER" "$CURRENT" "$WANT")"
  OK="$(printf '%s' "$VERDICT" | jq -r '.is_set and ((.mac_before | length) == 0 or .mac_after == .mac_before) and ((.lost_keys | length) == 0) and .current_agrees')"
  if [[ "$OK" != "true" ]]; then
    _error "$(printf '%s' "$VERDICT" | jq -r --arg before "$BEFORE" --arg wanted "$WANTED" --arg after "$AFTER" --arg current "$CURRENT" --arg want "$WANT" '
      "the card was rewritten and the result is NOT what was intended. before: " + $before + " intended: " + $wanted + " stored: " + $after + " running: " + (if ($current | length) == 0 then "not read" else $current end) + ". "
      + (if .is_set then "" else "The firewall flag does NOT read " + $want + " on the stored card. " end)
      + (if ((.mac_before | length) > 0 and .mac_after != .mac_before) then "THE MAC CHANGED, from " + .mac_before + " to " + .mac_after + ". The guest has very likely lost its network : cloud-init writes a netplan that matches on macaddress, and nothing on the Proxmox side shows it. Put the old MAC back on this card and reboot the guest. " else "" end)
      + (if (.lost_keys | length) > 0 then "SETTINGS WERE LOST by the write : " + (.lost_keys | join(", ")) + ". Writing net<N> replaces the whole option, so anything absent from what was sent is gone. Put them back explicitly. " else "" end)
      + (if .current_agrees then "" else "The STORED card carries the change but the RUNNING guest does not : PVE deferred it to the next reboot. Do not treat this card as changed until then." end)
    ')"
    exit 1
  fi

  jq -nc \
    --arg action "$ACTION" \
    --arg source "$SOURCE_TAG" \
    --arg node "$NODE" \
    --argjson vm_id "$VM_ID" \
    --arg vm_name "$VM_NAME" \
    --argjson vmnet_id "$VMNET_ID" \
    --arg key "$KEY" \
    --argjson want "$WANT" \
    --argjson already "$ALREADY" \
    --argjson verdict "$VERDICT" \
    --arg before "$BEFORE" \
    --arg after "$AFTER" \
    '{
      action: $action,
      source: $source,
      proxmox_node: $node,
      vm_id: $vm_id,
      vm_name: $vm_name,
      vm_vmnet_id: $vmnet_id,
      vm_network_device: $key,
      vm_network_mac: $verdict.mac_after,
      iface_firewall_before: (if $already then $want else (1 - $want) end),
      iface_firewall_after: (if $verdict.is_set then $want else (1 - $want) end),
      already_present: $already,
      net_before: $before,
      net_after: $after
    }' | _emit
done
