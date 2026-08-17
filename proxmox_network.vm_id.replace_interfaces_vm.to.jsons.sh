#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# move one network card of a VM to another bridge : delete then add.
#
# TWO MODES, AND THIS IS THE DESTRUCTIVE ONE
#   append  -> proxmox_network.vm_id.add_interfaces_vm.to.jsons.sh, which adds the next
#              netN and leaves every existing card alone. Use it when the VM must keep
#              its current attachments.
#   replace -> THIS script. It removes the card and creates it again on the new bridge.
#
# The verb says delete is inside, on purpose : the card is destroyed, not edited.
#
# WHAT IS PRESERVED, AND WHAT IS NOT
# The model is read from the existing card, so the caller does not repeat it. The
# FIREWALL flag is read back too. The MAC ADDRESS IS NOT PRESERVED : iface_macaddr is
# consumed by the role but not yet declared in the two forwarding helpers, so it cannot
# be passed from a devkit today. The new card therefore gets a fresh MAC.
#
# That matters : a DHCP reservation, an ipset or a firewall alias keyed on the old MAC
# will not follow. For the case this was written for, pulling a test VM off the
# management bridge, a new MAC is exactly what you want. For anything else, check first.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

show_example() {
  echo "  :: MOVE net0 OF VM 102 FROM vmbr0 TO THE SDN VNET net199"
  echo
  echo "    echo '{\"proxmox_node\":\"px-testing\",\"vm_id\":102,\"vm_vmnet_id\":0,\"iface_bridge\":\"net199\"}' \\"
  echo "      | $(basename "$0")"
  echo
  echo "  :: SEE WHAT THE VM HAS FIRST"
  echo
  echo "    echo \"102\" | proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh | jq -c"
  echo
  echo "  :: APPEND INSTEAD, KEEPING THE EXISTING CARDS"
  echo
  echo "    echo '{\"proxmox_node\":\"px-testing\",\"vm_id\":102,\"iface_model\":\"virtio\",\"iface_bridge\":\"net199\"}' \\"
  echo "      | proxmox_network.vm_id.add_interfaces_vm.to.jsons.sh"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - move one network card of a VM to another bridge"
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  STDIN :: [JSON] | $(basename "$0")"
  echo
  echo "  required : proxmox_node, vm_id, vm_vmnet_id, iface_bridge"
  echo "  optional : iface_model (default : read from the card being replaced)"
  echo
  echo "  DESTRUCTIVE : the card is deleted and recreated, its MAC changes."
  echo "  For a non destructive attach, use add_interfaces_vm."
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
  "INT::vm_id" "INT::vm_vmnet_id" "STR::iface_bridge" "STR::proxmox_node" "STR::action")

_err()   { devkit_utils.text.echo_error.to.text.to.stderr.sh "$1"; }
_trace() { devkit_utils.text.echo_trace.to.text.to.stderr.sh "$1"; }

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  _trace "$CURRENT_JSON_LINE"

  NODE=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.proxmox_node // empty')
  VMID=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.vm_id // empty')
  NETID=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r 'if .vm_vmnet_id == null then "" else .vm_vmnet_id end')
  BRIDGE=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.iface_bridge // empty')
  MODEL_IN=$(printf '%s' "$CURRENT_JSON_LINE" | jq -r '.iface_model // empty')

  ## vm_vmnet_id 0 is legitimate and must not be mistaken for absent, hence the null
  ## test above rather than // empty.
  [ -n "$NETID" ] || { _err "missing vm_vmnet_id"; exit 1; }

  #### #### ####
  #
  # 1. Read the card. This proves it exists BEFORE anything is destroyed, and it is
  #    where the model comes from when the caller did not give one.
  #
  CARD=$(printf '{"proxmox_node":"%s","vm_id":%s}\n' "$NODE" "$VMID" \
         | proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh --json 2>/dev/null \
         | jq -c --argjson n "$NETID" 'select(.vm_vmnet_id == $n)' || true)

  if [ -z "$CARD" ]; then
    _err "VM $VMID has no card net$NETID. Nothing was changed."
    _err "list what it really has : echo \"$VMID\" | proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh"
    exit 1
  fi

  OLD_BRIDGE=$(printf '%s' "$CARD" | jq -r '.vm_network_bridge // empty')
  OLD_MODEL=$(printf  '%s' "$CARD" | jq -r '.vm_network_type   // empty')
  OLD_FW=$(printf     '%s' "$CARD" | jq -r '.vm_network_firewall // empty')
  MODEL="${MODEL_IN:-$OLD_MODEL}"

  [ -n "$MODEL" ] || { _err "could not determine the card model, pass iface_model"; exit 1; }

  if [ "$OLD_BRIDGE" = "$BRIDGE" ]; then
    _trace "net$NETID is already on $BRIDGE : nothing to do"
    jq -c -n --arg node "$NODE" --argjson vm "$VMID" --argjson net "$NETID" \
      --arg bridge "$BRIDGE" --arg model "$MODEL" \
      '{action:"network_replace_interfaces_vm", source:"proxmox", proxmox_node:$node,
        vm_id:$vm, vm_vmnet_id:$net, iface_bridge:$bridge, iface_model:$model,
        verdict:"skipped", detail:"already on that bridge"}'
    continue
  fi

  _trace "replace : vm=$VMID net$NETID  $OLD_BRIDGE -> $BRIDGE  model=$MODEL firewall=${OLD_FW:-unset}"

  #### #### ####
  #
  # 2. Destroy, then recreate. Between the two the VM has one card less, which is why
  #    this is not the mode to use on a VM you are connected to through that card.
  #
  printf '{"proxmox_node":"%s","vm_id":%s,"vm_vmnet_id":%s}\n' "$NODE" "$VMID" "$NETID" \
    | proxmox_network.vm_id.delete_interfaces_vm.to.jsons.sh --json

  if [ -n "$OLD_FW" ]; then
    printf '{"proxmox_node":"%s","vm_id":%s,"iface_model":"%s","iface_bridge":"%s","iface_firewall":"%s"}\n' \
      "$NODE" "$VMID" "$MODEL" "$BRIDGE" "$OLD_FW" \
      | proxmox_network.vm_id.add_interfaces_vm.to.jsons.sh --json
  else
    printf '{"proxmox_node":"%s","vm_id":%s,"iface_model":"%s","iface_bridge":"%s"}\n' \
      "$NODE" "$VMID" "$MODEL" "$BRIDGE" \
      | proxmox_network.vm_id.add_interfaces_vm.to.jsons.sh --json
  fi

  #### #### ####
  #
  # 3. One summary line, so the composite is itself pipeable. The old bridge is carried
  #    because it is the only trace of where the card came from.
  #
  jq -c -n --arg node "$NODE" --argjson vm "$VMID" --argjson net "$NETID" \
    --arg from "$OLD_BRIDGE" --arg bridge "$BRIDGE" --arg model "$MODEL" --arg fw "${OLD_FW:-}" \
    '{action:"network_replace_interfaces_vm", source:"proxmox", proxmox_node:$node,
      vm_id:$vm, vm_vmnet_id:$net,
      iface_bridge_from:$from, iface_bridge:$bridge, iface_model:$model,
      iface_firewall:(if $fw == "" then null else $fw end),
      verdict:"ok", detail:"card recreated, MAC changed"}'

done
