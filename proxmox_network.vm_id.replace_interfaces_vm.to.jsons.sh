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
# WHAT IS PRESERVED
# The MODEL is read from the existing card, so the caller does not repeat it. The FIREWALL
# flag is read back too. The INTERFACE ID is asked for explicitly on the way back, so net3
# comes back as net3 and never lands on top of another card - see the comment on the add
# below, it is the one thing here that could damage a card nobody asked to touch.
#
# The MAC is read back and resent. It used to change, and this header used to call that
# wanted : it was a limitation, not a choice - iface_macaddr was consumed by the role but
# undeclared in the two forwarding helpers, so a devkit could not pass it. It cost two
# guests, MEASURED : cloud-init writes a netplan carrying a match on macaddress, so a new
# MAC makes netplan apply answer "Cannot find unique matching interface" and the guest
# loses its network. Nothing shows on the Proxmox side - the api reports a healthy card and
# only the guest knows it is cut. A DHCP reservation, an ipset or a firewall alias keyed on
# the MAC breaks the same way.
#
# A replace that does not keep the MAC is not a replace. Want a fresh MAC ? Call delete then
# add yourself, without iface_macaddr. A card whose MAC cannot be read is REFUSED here,
# before anything is destroyed, the same way an unreadable model already is.
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
  echo "  DESTRUCTIVE : the card is deleted and recreated. Its slot, model, firewall flag"
  echo "  and MAC are preserved, and a card whose MAC cannot be read is refused before"
  echo "  anything is destroyed. For a non destructive attach, use add_interfaces_vm."
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
  OLD_MAC=$(printf    '%s' "$CARD" | jq -r '.vm_network_mac    // empty')
  MODEL="${MODEL_IN:-$OLD_MODEL}"

  [ -n "$MODEL" ] || { _err "could not determine the card model, pass iface_model"; exit 1; }

  ## Refused BEFORE the delete, not after. The MAC is read positionally from the first
  ## segment, which the api normalises to <model>=<MAC> : unreadable means the card is not
  ## shaped as expected, and recreating it would hand the guest a MAC its netplan does not
  ## match. There is no safe way to put that back, so we do not take the card apart.
  if [ -z "$OLD_MAC" ]; then
    _err "could not read the MAC of net$NETID on VM $VMID. NOTHING was changed."
    _err "a replace that cannot resend the MAC would cut the guest : see the header."
    _err "read the card : echo \"$VMID\" | proxmox_network.vm_id.list_interfaces_vm.to.jsons.sh"
    exit 1
  fi

  if [ "$OLD_BRIDGE" = "$BRIDGE" ]; then
    _trace "net$NETID is already on $BRIDGE : nothing to do"
    jq -c -n --arg node "$NODE" --argjson vm "$VMID" --argjson net "$NETID" \
      --arg bridge "$BRIDGE" --arg model "$MODEL" --arg mac "$OLD_MAC" \
      '{action:"network_replace_interfaces_vm", source:"proxmox", proxmox_node:$node,
        vm_id:$vm, vm_vmnet_id:$net, iface_bridge:$bridge, iface_model:$model,
        iface_macaddr:$mac,
        verdict:"skipped", detail:"already on that bridge, nothing destroyed"}'
    continue
  fi

  _trace "replace : vm=$VMID net$NETID  $OLD_BRIDGE -> $BRIDGE  model=$MODEL mac=$OLD_MAC firewall=${OLD_FW:-unset}"

  #### #### ####
  #
  # 2. Destroy, then recreate. Between the two the VM has one card less, which is why
  #    this is not the mode to use on a VM you are connected to through that card.
  #
  printf '{"proxmox_node":"%s","vm_id":%s,"vm_vmnet_id":%s}\n' "$NODE" "$VMID" "$NETID" \
    | proxmox_network.vm_id.delete_interfaces_vm.to.jsons.sh --json

  ## vm_vmnet_id is passed EXPLICITLY, and that is not a detail. Left out, add_interfaces_vm
  ## derives the id by COUNTING the cards that remain - the card just deleted is gone, so
  ## the count is one short and only lands on the right id when the ids happen to run 0..n-1
  ## and the moved card was the last of them.
  ##
  ## Take a VM with net0 and net1 and move net0 : the delete leaves one card, the count says
  ## 1, and the add recreates net1 - ON TOP OF THE net1 THAT IS STILL THERE. A move of one
  ## card would silently destroy another. Asking for the id we just deleted is the whole
  ## point of a replace, and it costs one key.
  ##
  ## iface_macaddr goes to BOTH branches : it is what makes this a replace rather than a
  ## new card. The branch itself is only about the firewall flag, which must be resent when
  ## the card had one and left out when it had none.
  if [ -n "$OLD_FW" ]; then
    printf '{"proxmox_node":"%s","vm_id":%s,"vm_vmnet_id":%s,"iface_model":"%s","iface_bridge":"%s","iface_macaddr":"%s","iface_firewall":"%s"}\n' \
      "$NODE" "$VMID" "$NETID" "$MODEL" "$BRIDGE" "$OLD_MAC" "$OLD_FW" \
      | proxmox_network.vm_id.add_interfaces_vm.to.jsons.sh --json
  else
    printf '{"proxmox_node":"%s","vm_id":%s,"vm_vmnet_id":%s,"iface_model":"%s","iface_bridge":"%s","iface_macaddr":"%s"}\n' \
      "$NODE" "$VMID" "$NETID" "$MODEL" "$BRIDGE" "$OLD_MAC" \
      | proxmox_network.vm_id.add_interfaces_vm.to.jsons.sh --json
  fi

  #### #### ####
  #
  # 3. One summary line, so the composite is itself pipeable. The old bridge is carried
  #    because it is the only trace of where the card came from.
  #
  jq -c -n --arg node "$NODE" --argjson vm "$VMID" --argjson net "$NETID" \
    --arg from "$OLD_BRIDGE" --arg bridge "$BRIDGE" --arg model "$MODEL" --arg fw "${OLD_FW:-}" \
    --arg mac "$OLD_MAC" \
    '{action:"network_replace_interfaces_vm", source:"proxmox", proxmox_node:$node,
      vm_id:$vm, vm_vmnet_id:$net,
      iface_bridge_from:$from, iface_bridge:$bridge, iface_model:$model,
      iface_macaddr:$mac,
      iface_firewall:(if $fw == "" then null else $fw end),
      verdict:"ok", detail:"card recreated, MAC preserved"}'

done
