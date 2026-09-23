#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox__inc.show_sdn.request.sh
#
# SHARED BY THE show_sdn FAMILY, the engine and its api twin : it knows nothing about the SDN, it
# reads a scope, an output and a set of NETWORKS. The show_firewall family has its own request
# include because its tokens are guest ids ; a network is named, not numbered, so the two parsers
# cannot be one without pretending a vnet name is a vm_id.
#
# Reads the options and the input ONCE, validates them, and prints one json line describing the
# request :
#
#   {"scope":"sdn_vnets","output":"table","networks":[{"vnet":"net143","cidr":null}],"scenario_name":null}
#
# scope     sdn_vnet | sdn_vnets | scenario | dc | all
#           without --scope : a positional name means sdn_vnet, names on stdin mean sdn_vnets, no
#           stdin means scenario (the bridges the active scenario declares, read in the manifest)
# output    json (default) | text | table
# networks  the networks to read, in the order given, duplicates folded ; null for dc and all
#           (every network the cluster declares)
#
# THE OPTIONAL CIDR, and why it is read here. A network the SDN declares carries its cidr in its
# subnet, so the engine reads it. A legacy vmbr bridge is NOT an SDN object : nothing in the api
# holds its cidr, and the live SNAT rules are grouped by source cidr, so without it the egress of
# such a bridge cannot be counted. A caller that knows the cidr - range42-context does, it resolves
# the scenario manifest - passes it on stdin next to the name. Nothing is derived from a name here :
# a convention on the octet of a bridge name belongs to the scenario, not to a devkit.
#
# On stdin, a line is either a bare network name or a json object naming one in vnet, subnet_vnet
# or bridge, with an optional cidr. Every other key of the object is ignored, so the output of
# proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh pipes in as it is.
#
# Exit 1 with a message on stderr when the request cannot be honoured : two scopes, an unknown
# scope, a line that names no network, sdn_vnet with more than one name, sdn_vnets without stdin,
# scenario without a manifest.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - shared request parser of the show_sdn engine and its twin "
  echo
  echo OPTIONS
  echo
  echo "  [STDIN :: networks] | $(basename "$0") [--scope sdn_vnet|sdn_vnets|scenario|dc|all] [--json|--text|--table] [vnet]"
  echo
  echo "  prints one json line : {scope, output, networks, scenario_name}"
  echo "  a network on stdin : a bare name, or a json object naming it in vnet, subnet_vnet or"
  echo "  bridge, with an optional cidr (the only key read besides the name)"
  echo
  echo
  exit 1
fi

_fail() {
  devkit_utils.text.echo_error.to.text.to.stderr.sh " $1"
  exit 1
}

SCOPE=""
OUTPUT="json"
POS_VNET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --scope)
    [[ -n "${2:-}" ]] || _fail "--scope needs a value : sdn_vnet, sdn_vnets, scenario, dc or all"
    [[ -z "$SCOPE" ]] || _fail "--scope given twice (${SCOPE} then ${2})"
    SCOPE="$2"
    shift 2
    ;;
  --scope=*)
    [[ -z "$SCOPE" ]] || _fail "--scope given twice (${SCOPE} then ${1#--scope=})"
    SCOPE="${1#--scope=}"
    shift
    ;;
  --json | --text | --table)
    OUTPUT="${1#--}"
    shift
    ;;
  -*)
    _fail "unknown option : $1"
    ;;
  *)
    [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_.-]*$ ]] || _fail "not a network name : $1"
    [[ -z "$POS_VNET" ]] || _fail "only one network may be given as an argument : pipe several names on stdin"
    POS_VNET="$1"
    shift
    ;;
  esac
done

case "$SCOPE" in
"" | sdn_vnet | sdn_vnets | scenario | dc | all) ;;
*) _fail "unknown scope : ${SCOPE} (sdn_vnet, sdn_vnets, scenario, dc or all)" ;;
esac

if [[ -z "$SCOPE" ]]; then
  if [[ -n "$POS_VNET" ]]; then SCOPE="sdn_vnet"
  elif [[ ! -t 0 ]]; then SCOPE="sdn_vnets"
  else SCOPE="scenario"; fi
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# the networks of the request, by scope
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

NETWORKS_JSON="null"

_read_stdin_networks() {
  # a bare name, or a json object naming a network in vnet, subnet_vnet or bridge (+ optional cidr)
  local l parsed
  [[ ! -t 0 ]] || _fail "no input on stdin : pipe the network names (one per line, plain or json)"
  parsed=$(while IFS= read -r l; do
    [ -n "${l//[[:space:]]/}" ] || continue
    if [[ "$l" =~ ^[[:space:]]*[A-Za-z][A-Za-z0-9_.-]*[[:space:]]*$ ]]; then
      printf '{"vnet":"%s","cidr":null}\n' "$(printf '%s' "$l" | tr -d '[:space:]')"
    elif printf '%s\n' "$l" | jq -e 'type == "object" and ((.vnet // .subnet_vnet // .bridge // null) | type) == "string"' >/dev/null 2>&1; then
      printf '%s\n' "$l" | jq -c '
        {
          vnet: (.vnet // .subnet_vnet // .bridge),
          cidr: ((.cidr // .subnet_cidr) // null)
        }'
    else
      printf '{"bad_line":%s}\n' "$(printf '%s' "$l" | jq -R -c .)"
    fi
  done)
  local bad
  bad=$(printf '%s\n' "$parsed" | jq -r -s 'map(select(.bad_line != null)) | .[0].bad_line // empty')
  [[ -z "$bad" ]] || _fail "cannot read a network name from this line : ${bad}"
  # duplicates folded on the NAME, the first line of a name keeping its cidr
  NETWORKS_JSON=$(printf '%s\n' "$parsed" | jq -s -c '
    reduce .[] as $x ([]; if ([ .[].vnet ] | index($x.vnet)) == null then . + [$x] else . end)')
}

case "$SCOPE" in
sdn_vnet)
  if [[ -n "$POS_VNET" ]]; then
    NETWORKS_JSON=$(jq -n -c --arg v "$POS_VNET" '[ { vnet: $v, cidr: null } ]')
  else
    _read_stdin_networks
    n=$(printf '%s' "$NETWORKS_JSON" | jq 'length')
    [[ "$n" -eq 1 ]] || _fail "sdn_vnet takes exactly one network, got ${n} : use --scope sdn_vnets for a set"
  fi
  ;;
sdn_vnets)
  if [[ -n "$POS_VNET" ]]; then
    NETWORKS_JSON=$(jq -n -c --arg v "$POS_VNET" '[ { vnet: $v, cidr: null } ]')
  else
    _read_stdin_networks
    [[ "$(printf '%s' "$NETWORKS_JSON" | jq 'length')" -gt 0 ]] || _fail "no network read on stdin : pipe one name per line, or ask for a scope (--scope scenario, dc, all)"
  fi
  ;;
scenario)
  [[ -n "${RANGE42_ACTIVE_CONFIG_DIR:-}" ]] || _fail "no active workspace in this shell (RANGE42_ACTIVE_CONFIG_DIR is empty) - run : range42-context use <codename> <scenario>"
  MANIFEST="${RANGE42_ACTIVE_CONFIG_DIR%/}/scenario/manifest/scenario_vms.json"
  [[ -f "$MANIFEST" ]] || _fail "the active scenario has no manifest : ${MANIFEST}"
  # the bridges the scenario declares, vms and templates alike : the cidr is NOT taken from here,
  # a manifest holds no cidr and this include derives nothing from a name
  NETWORKS_JSON=$(jq -c '
    [ ((.vms // []) + (.templates // []))[]
      | .bridge
      | select(. != null and . != "")
    ]
    | unique
    | map({ vnet: ., cidr: null })' "$MANIFEST" 2>/dev/null) || _fail "cannot read the bridges of the manifest : ${MANIFEST}"
  [[ "$(printf '%s' "$NETWORKS_JSON" | jq 'length')" -gt 0 ]] || _fail "the manifest declares no bridge : ${MANIFEST}"
  # the name travels with the request : the renderer titles the table with the perimeter that was ASKED
  SCENARIO_NAME=$(jq -r '.scenario // empty' "$MANIFEST" 2>/dev/null || true)
  ;;
dc | all)
  NETWORKS_JSON="null"
  ;;
esac

jq -n -c --arg scope "$SCOPE" --arg output "$OUTPUT" --argjson networks "$NETWORKS_JSON" \
  --arg scenario_name "${SCENARIO_NAME:-}" \
  '
  {
    scope: $scope,
    output: $output,
    networks: $networks,
    scenario_name: (if $scenario_name == "" then null else $scenario_name end)
  }'
