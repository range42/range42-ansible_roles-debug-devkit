#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# SHARED LOGIC for enable / disable / toggle_outgoing_nat.
#
# Turning outbound NAT on or off for one subnet is NOT one call, it is three, and skipping
# the last one is the classic mistake :
#
#     1. update_sdn_subnet     snat=1|0        the declaration changes
#     2. apply_sdn                             the change becomes live, asynchronously
#     3. delete_extra_snat_rules   want=1|0     the live iptables rules are reconciled
#
# Step 3 is not optional in EITHER direction. Going up, an apply adds one SNAT rule per
# active subnet every time it runs, so the count has to be brought back to one. Going down
# is worse : snat=0 removes the post-down hook from the configuration BEFORE that hook ever
# runs, leaving the live rule orphaned. Without step 3, a subnet set to snat=0 keeps its
# internet access and nothing says so.
#
# The three steps need three different values : the vnet and the id for the update, the
# CIDR for the reconciliation. Only the id is asked of the caller ; the rest is read from
# list_sdn_subnets, which also proves the subnet exists before anything is written.
#
# USAGE (sourced or called) :  <this> <subnet_id> <1|0|toggle>
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

SDN_SUBNET_ID="${1:-}"
SDN_WANT="${2:-}"

_err() { devkit_utils.text.echo_error.to.text.to.stderr.sh "$1"; }

[ -n "$SDN_SUBNET_ID" ] || { _err "missing subnet id"; exit 1; }
case "$SDN_WANT" in 0|1|toggle) ;; *) _err "second argument must be 1, 0 or toggle"; exit 1 ;; esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# 1. Read the subnet. This is what turns one input into the three values the chain needs,
#    and it fails BEFORE any write if the id does not exist.
#
SUBNET_LINE=$(proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh --json 2>/dev/null \
  | jq -c --arg id "$SDN_SUBNET_ID" 'select(.subnet == $id)' || true)

if [ -z "$SUBNET_LINE" ]; then
  _err "subnet '$SDN_SUBNET_ID' not found on the cluster. Nothing was changed."
  _err "list the real ids with : proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh | jq -r .subnet"
  exit 1
fi

SDN_NODE=$(printf '%s' "$SUBNET_LINE"  | jq -r '.proxmox_node // empty')
SDN_VNET=$(printf '%s' "$SUBNET_LINE"  | jq -r '.subnet_vnet // empty')
SDN_CIDR=$(printf '%s' "$SUBNET_LINE"  | jq -r '.subnet_cidr // empty')
SDN_SNAT_NOW=$(printf '%s' "$SUBNET_LINE" | jq -r '.subnet_snat // 0')

[ -n "$SDN_VNET" ] || { _err "the subnet carries no vnet, cannot address it for an update"; exit 1; }
# The reconciliation matches on the source network : without a CIDR it would either do
# nothing or, unanchored, match far too much. Refuse rather than guess.
[ -n "$SDN_CIDR" ] || { _err "the subnet carries no cidr, refusing to reconcile blindly"; exit 1; }

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# The toggle is resolved HERE, once, from the state just read.
#
if [ "$SDN_WANT" = "toggle" ]; then
  if [ "$SDN_SNAT_NOW" = "1" ]; then SDN_WANT=0 ; else SDN_WANT=1 ; fi
fi

devkit_utils.text.echo_trace.to.text.to.stderr.sh \
  "outgoing_nat : subnet=$SDN_SUBNET_ID vnet=$SDN_VNET cidr=$SDN_CIDR snat_now=$SDN_SNAT_NOW -> want=$SDN_WANT"

if [ "$SDN_SNAT_NOW" = "$SDN_WANT" ]; then
  devkit_utils.text.echo_trace.to.text.to.stderr.sh \
    "already at snat=$SDN_WANT in the declaration ; the chain still runs so the LIVE rules get reconciled"
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# 2. Declare.
#
printf '{"proxmox_node":"%s","sdn_vnet":"%s","sdn_subnet_id":"%s","sdn_subnet_snat":%s}\n' \
  "$SDN_NODE" "$SDN_VNET" "$SDN_SUBNET_ID" "$SDN_WANT" \
  | proxmox_network.sdn_vnet.update_sdn_subnet.to.jsons.sh --json

#
# 3. Make it live. The devkit waits for the background task, so what follows really runs
#    against a converged cluster.
#
printf '{"proxmox_node":"%s"}\n' "$SDN_NODE" \
  | proxmox_network.datacenter.apply_sdn.to.jsons.sh --json

#
# 4. Reconcile the live rules. NEVER drop this step.
#
printf '{"proxmox_node":"%s","sdn_subnet_cidr":"%s","sdn_snat_want":%s}\n' \
  "$SDN_NODE" "$SDN_CIDR" "$SDN_WANT" \
  | proxmox_network.sdn_subnet_cidr.delete_extra_snat_rules.to.jsons.sh --json

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# One summary line, so the composite is itself pipeable.
#
jq -c -n \
  --arg action "network_outgoing_nat" \
  --arg node "$SDN_NODE" \
  --arg subnet "$SDN_SUBNET_ID" \
  --arg vnet "$SDN_VNET" \
  --arg cidr "$SDN_CIDR" \
  --argjson was "$SDN_SNAT_NOW" \
  --argjson now "$SDN_WANT" \
  '{action:$action, source:"proxmox", proxmox_node:$node,
    subnet:$subnet, subnet_vnet:$vnet, subnet_cidr:$cidr,
    outgoing_nat_was:$was, outgoing_nat_now:$now}'
