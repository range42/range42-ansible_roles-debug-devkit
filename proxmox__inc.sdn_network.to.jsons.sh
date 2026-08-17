#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# SHARED LOGIC for create_sdn_network / delete_sdn_network.
#
# A usable SDN network is never one call. It is a zone, a vnet, a subnet, an apply, and
# a reconciliation of the live rules, in that order, and the reverse order to take it
# down. Wrapping the two directions in one include is what keeps them symmetric.
#
#   create :  add_zone -> add_vnet -> add_subnet -> apply -> reconcile want=1
#   delete :  del_subnet -> del_vnet -> del_zone -> apply -> reconcile want=0
#
# WHY DELETE READS BEFORE IT WRITES
# Proxmox answers HTTP 500 "does not exist" when asked to delete something absent. The
# obvious workaround, tolerating that 500, means matching an error string that changes
# between versions, and it would also swallow the OTHER 500s, the ones that are real
# failures. So instead each object is looked up first : absent means "nothing to do",
# and it is REPORTED as skipped rather than passed over in silence. Same reason the
# reconciliation exists at all, and the same reason a delete on an empty cluster has to
# succeed : without it this sequence could only ever run once.
#
# WHY THE APPLY AND THE RECONCILIATION ARE NOT OPTIONAL
# The apply is what makes a pending object live. And each apply appends one SNAT rule
# per subnet at snat=1, measured at +12 per apply on a 12 bridge node, so the count has
# to be brought back to what the declaration says. See 1.6 of the SDN plan : only the
# snat=0 path orphans a rule, a franc teardown does play the post-down, but running the
# reconciliation in both cases costs nothing and it is what proves the state.
#
# USAGE (sourced or called) :
#   <this> create <node> <zone> <vnet> <cidr> [gateway] [snat]
#   <this> delete <node> <zone> <vnet> <cidr>
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

MODE="${1:-}"
SDN_NODE="${2:-}"
SDN_ZONE="${3:-}"
SDN_VNET="${4:-}"
SDN_CIDR="${5:-}"
SDN_GW="${6:-}"
SDN_SNAT="${7:-1}"

_err()   { devkit_utils.text.echo_error.to.text.to.stderr.sh "$1"; }
_trace() { devkit_utils.text.echo_trace.to.text.to.stderr.sh "$1"; }

case "$MODE" in create|delete) ;; *) _err "first argument must be create or delete"; exit 1 ;; esac
[ -n "$SDN_NODE" ] || { _err "missing proxmox_node"; exit 1; }
[ -n "$SDN_ZONE" ] || { _err "missing sdn_zone"; exit 1; }
[ -n "$SDN_VNET" ] || { _err "missing sdn_vnet"; exit 1; }
[ -n "$SDN_CIDR" ] || { _err "missing sdn_subnet cidr"; exit 1; }

## The subnet id is derived, not guessed : Proxmox builds it as <zone>-<network>-<mask>.
## Deriving it here means the caller never has to know that rule, and it is the same
## string add_sdn_subnet reads back after creation.
SDN_SUBNET_ID="${SDN_ZONE}-${SDN_CIDR//\//-}"

## Per step verdict, accumulated as a JSON array so the summary can carry it.
STEPS="[]"
_step() {
  local name="$1" verdict="$2" detail="${3:-}"
  STEPS=$(printf '%s' "$STEPS" | jq -c --arg n "$name" --arg v "$verdict" --arg d "$detail" \
          '. + [{step:$n, verdict:$v, detail:$d}]')
  _trace "  $verdict  $name${detail:+  ($detail)}"
}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# Existence probes. Read only, and the reason delete is idempotent.
#
## LES SONDES, ET LES DEUX PIEGES QU'ELLES EVITENT
##
## 1. ALIMENTER, jamais couper. Le normaliseur en amont de chaque devkit fait :
##
##        { [ -t 0 ] && printf "%s\n" "$VAULT_NODE" || cat -; } | ...
##
##    donc un stdin qui n'est PAS un tty le fait LIRE stdin. Depuis un terminal il
##    retombe sur le noeud du vault et tout marche ; depuis un script stdin n'est jamais
##    un tty, donc il lit, et un < /dev/null lui sert un flux vide. La sonde conclut
##    alors "absent" sur un objet bien present. C'est le bug de fcd9599.
##
## 2. NE PAS CONFONDRE "absent" ET "je n'ai pas pu regarder". Avec pipefail, un devkit
##    en echec rend un pipeline non nul, exactement comme un jq -e sans correspondance.
##    Tester seulement zero/non-zero ferait donc d'une panne d'API un "skipped"
##    silencieux : on croirait avoir constate l'absence. Le statut du devkit est donc
##    releve A PART, et une panne arrete la sequence au lieu de la faire mentir.
_list_json() {
  printf '{"proxmox_node":"%s"}\n' "$SDN_NODE" | "$1" --json 2>/dev/null
}

_lookup() {
  local devkit="$1" field="$2" value="$3" out rc
  ## Le || rc=$? n'est pas cosmetique : sous set -e, une affectation par substitution
  ## qui echoue interrompt le script, et le rc=$? de la ligne suivante ne serait
  ## jamais atteint.
  out=$(_list_json "$devkit") && rc=0 || rc=$?
  if [ "$rc" -ne 0 ]; then
    _err "lookup via $devkit en echec (rc=$rc) : refus de traiter cela comme une absence"
    exit 1
  fi
  printf '%s\n' "$out" | jq -e --arg v "$value" "select(.${field} == \$v)" >/dev/null 2>&1
}

_zone_exists()   { _lookup proxmox_network.datacenter.list_sdn_zones.to.jsons.sh   zone   "$SDN_ZONE" ; }
_vnet_exists()   { _lookup proxmox_network.datacenter.list_sdn_vnets.to.jsons.sh   vnet   "$SDN_VNET" ; }
_subnet_exists() { _lookup proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh subnet "$SDN_SUBNET_ID" ; }

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

_trace "sdn_network $MODE : node=$SDN_NODE zone=$SDN_ZONE vnet=$SDN_VNET cidr=$SDN_CIDR id=$SDN_SUBNET_ID"

if [ "$MODE" = create ]; then

  if _zone_exists ; then
    _step add_zone skipped "already present"
  else
    printf '{"proxmox_node":"%s","sdn_zone":"%s"}\n' "$SDN_NODE" "$SDN_ZONE" \
      | proxmox_network.datacenter.add_sdn_zone.to.jsons.sh --json
    _step add_zone ok
  fi

  if _vnet_exists ; then
    _step add_vnet skipped "already present"
  else
    printf '{"proxmox_node":"%s","sdn_zone":"%s","sdn_vnet":"%s"}\n' "$SDN_NODE" "$SDN_ZONE" "$SDN_VNET" \
      | proxmox_network.datacenter.add_sdn_vnet.to.jsons.sh --json
    _step add_vnet ok
  fi

  if _subnet_exists ; then
    _step add_subnet skipped "already present"
  else
    ## The gateway is optional : a subnet without one is legal, it just has no router.
    if [ -n "$SDN_GW" ]; then
      printf '{"proxmox_node":"%s","sdn_vnet":"%s","sdn_subnet":"%s","sdn_subnet_gateway":"%s","sdn_subnet_snat":%s}\n' \
        "$SDN_NODE" "$SDN_VNET" "$SDN_CIDR" "$SDN_GW" "$SDN_SNAT" \
        | proxmox_network.sdn_vnet.add_sdn_subnet.to.jsons.sh --json
    else
      printf '{"proxmox_node":"%s","sdn_vnet":"%s","sdn_subnet":"%s","sdn_subnet_snat":%s}\n' \
        "$SDN_NODE" "$SDN_VNET" "$SDN_CIDR" "$SDN_SNAT" \
        | proxmox_network.sdn_vnet.add_sdn_subnet.to.jsons.sh --json
    fi
    _step add_subnet ok
  fi

  printf '{"proxmox_node":"%s"}\n' "$SDN_NODE" \
    | proxmox_network.datacenter.apply_sdn.to.jsons.sh --json
  _step apply ok

  printf '{"proxmox_node":"%s","sdn_subnet_cidr":"%s","sdn_snat_want":%s}\n' \
    "$SDN_NODE" "$SDN_CIDR" "$SDN_SNAT" \
    | proxmox_network.sdn_subnet_cidr.delete_extra_snat_rules.to.jsons.sh --json
  _step reconcile ok "want=$SDN_SNAT"

else

  ## Imposed order : a vnet still holding a subnet cannot go, nor a zone holding a vnet.
  if _subnet_exists ; then
    printf '{"proxmox_node":"%s","sdn_vnet":"%s","sdn_subnet_id":"%s"}\n' \
      "$SDN_NODE" "$SDN_VNET" "$SDN_SUBNET_ID" \
      | proxmox_network.sdn_vnet.delete_sdn_subnet.to.jsons.sh --json
    _step del_subnet ok
  else
    _step del_subnet skipped "not present"
  fi

  if _vnet_exists ; then
    printf '{"proxmox_node":"%s","sdn_vnet":"%s"}\n' "$SDN_NODE" "$SDN_VNET" \
      | proxmox_network.datacenter.delete_sdn_vnet.to.jsons.sh --json
    _step del_vnet ok
  else
    _step del_vnet skipped "not present"
  fi

  if _zone_exists ; then
    printf '{"proxmox_node":"%s","sdn_zone":"%s"}\n' "$SDN_NODE" "$SDN_ZONE" \
      | proxmox_network.datacenter.delete_sdn_zone.to.jsons.sh --json
    _step del_zone ok
  else
    _step del_zone skipped "not present"
  fi

  ## Applied even when everything was skipped : that is what converges the running
  ## config, and it is cheap. It also means a second run is a clean no-op.
  printf '{"proxmox_node":"%s"}\n' "$SDN_NODE" \
    | proxmox_network.datacenter.apply_sdn.to.jsons.sh --json
  _step apply ok

  ## want=0 on the way out : a franc teardown does play the post-down, but the snat=0
  ## path does not, and this is the only guard that proves which one happened.
  printf '{"proxmox_node":"%s","sdn_subnet_cidr":"%s","sdn_snat_want":0}\n' \
    "$SDN_NODE" "$SDN_CIDR" \
    | proxmox_network.sdn_subnet_cidr.delete_extra_snat_rules.to.jsons.sh --json
  _step reconcile ok "want=0"

fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# One summary line, so the composite is itself pipeable and its verdict is machine
# readable. skipped is counted apart from ok : it is information, not an error.
#
jq -c -n \
  --arg action "network_${MODE}_sdn_network" \
  --arg node "$SDN_NODE" \
  --arg zone "$SDN_ZONE" \
  --arg vnet "$SDN_VNET" \
  --arg cidr "$SDN_CIDR" \
  --arg subnet "$SDN_SUBNET_ID" \
  --argjson steps "$STEPS" \
  '{action:$action, source:"proxmox", proxmox_node:$node,
    zone:$zone, vnet:$vnet, subnet:$subnet, subnet_cidr:$cidr,
    steps:$steps,
    steps_ok:      ($steps | map(select(.verdict=="ok"))      | length),
    steps_skipped: ($steps | map(select(.verdict=="skipped")) | length)}'
