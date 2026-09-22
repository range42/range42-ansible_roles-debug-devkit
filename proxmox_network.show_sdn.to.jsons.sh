#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_network.show_sdn.to.jsons.sh
#
# The engine of the show_sdn view : per network, what the SDN DECLARES (its vnet, its subnet, its
# outgoing nat, its port isolation) beside what the node actually CARRIES (the live SNAT rules that
# forward its traffic). It is the devkit behind `range42-context networks-show-sdn` and
# `networks-internet-list`, usable on its own at any grain.
#
# THE DECLARATION AND THE LIVE STATE ARE TWO DIFFERENT THINGS, and that gap is the whole point of
# this view. A subnet at snat=1 that was never applied forwards nothing. A subnet at snat=0 whose
# legacy bridge stanza still writes a MASQUERADE forwards anyway. An apply is an ifreload, which
# replays the post-up hook of EVERY active subnet, so a network can carry five rules where one was
# meant : the count says so. These rules live in /etc/network/interfaces.d and are not api objects,
# so they are read on the node over SSH - the one read no api can replace.
#
# WHAT IT DOES NOT DO. It knows nothing of roles, of scope labels or of vm counts : those live in
# the scenario manifest, so resolving them stays with range42-context. This engine joins the three
# reads and nothing else. It derives nothing from a network NAME either : the cidr of a legacy
# vmbr bridge comes with the request or stays unknown.
#
# One engine, five scopes, four wrappers named by the grain. The api fast path lives once, in
# proxmox_network.show_sdn_with_api.to.jsons.sh ; this file delegates to it when the api answers
# and otherwise composes the existing readers (ansible path).
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="show_sdn"
SOURCE_TAG="proxmox"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: THE ACTIVE SCENARIO (no stdin), THE WHOLE DATACENTER, ONE NETWORK"
  echo
  echo "    $(basename "$0") --table"
  echo "    $(basename "$0") --scope dc --table"
  echo "    $(basename "$0") net143 --table"
  echo
  echo "  :: A SET OF NETWORKS ON STDIN (plain names or json lines)"
  echo
  local STDIN_JSON_DATA=(
    '{"vnet":"net143"}'
    '{"vnet":"vmbr142","cidr":"192.168.142.0/24"}'
  )
  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"' --json/'
  echo
  echo "    printf 'net143\\nnet144\\n' | $(basename "$0") --table"
  echo
  echo "  :: THE SUBNETS OF THE CLUSTER PIPED IN AS THEY COME"
  echo
  echo "    proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh | $(basename "$0") --table"
  echo
  echo "  :: WHAT IS OPEN, AND WHAT CARRIES MORE RULES THAN IT SHOULD"
  echo
  echo "    $(basename "$0") --scope dc --json | jq -c 'select(.internet == \"YES\")'"
  echo "    $(basename "$0") --scope dc --json | jq -c 'select((.snat_rules // 0) > 1)'"
  echo
  echo "  :: KEEP THE ANSIBLE PATH EVEN WHEN THE API ANSWERS"
  echo
  echo "    RANGE42_PROXMOX_API_FORCE=off $(basename "$0") --table"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the declared SDN of a network beside the live rules that forward it "
  echo
  echo OPTIONS
  echo
  echo "                       $(basename "$0") [-h|--help]"
  echo "  [STDIN :: networks] | $(basename "$0") [--scope sdn_vnet|sdn_vnets|scenario|dc|all] [--json|--text|--table] [vnet]"
  echo
  echo "  --json     one json object per line (default)"
  echo "  --text     one line of words per json line"
  echo "  --table    one row per network, then the networks the sdn does not declare, then the live"
  echo "             rules no declared network accounts for, then the errors"
  echo ""
  echo SCOPES
  echo
  echo "  sdn_vnet   one network : one name on stdin or as the argument"
  echo "  sdn_vnets  a set : one name per line on stdin, plain or json, duplicates folded, order kept"
  echo "  scenario   the bridges the active scenario declares, read in the workspace manifest"
  echo "  dc, all    every network the cluster declares ; today the node of the vault, one node per workspace"
  echo
  echo "  Without --scope : an argument means sdn_vnet, names on stdin mean sdn_vnets, no stdin"
  echo "  means scenario."
  echo ""
  echo "  THE OPTIONAL CIDR. A network the SDN declares carries its cidr in its subnet. A legacy"
  echo "  vmbr bridge is not an SDN object, so nothing here holds its cidr - and the live rules are"
  echo "  grouped by source cidr. Pass it next to the name on stdin, {\"vnet\":\"vmbr142\","
  echo "  \"cidr\":\"192.168.142.0/24\"}, or its rules stay unknown. Nothing is derived from a name :"
  echo "  a convention on the octet of a bridge name belongs to the scenario, not to a devkit."
  echo ""
  echo LINES
  echo
  echo "  level network      a network the cluster declares : vnet, cidr, zone, subnet, subnet_cidr,"
  echo "                     subnet_gateway, subnet_snat, subnets, vnet_zone, vnet_isolate_ports,"
  echo "                     outgoing_nat (on, off, no-subnet), isolated, snat_rules, snat_origin"
  echo "                     (sdn, legacy, mixed), snat_out_iface, internet (YES, NO, ?)"
  echo "  level undeclared   a network that was ASKED and that the sdn does not know : a legacy vmbr"
  echo "                     bridge is exactly that, and its live rules still count with a cidr"
  echo "  level rules_only   at scope dc and all : a live rule whose source network no subnet"
  echo "                     declares, an egress the sdn does not account for"
  echo "  level error        the live rules could not be read (reason) ; then snat_rules is null and"
  echo "                     internet says ? - an unread rule is not an absent rule"
  echo
  echo "  THE VERDICT. internet follows the LIVE rules, never the declaration : a legacy MASQUERADE"
  echo "  forwards just as well, and a subnet at snat=1 that was never applied forwards nothing."
  echo "  A network whose rules have SEVERAL SHAPES is named mixed, and every gesture leaves it"
  echo "  alone : the reconciliation deletes per source network and could take the wrong one."
  echo ""
  echo PATHS
  echo
  echo "  When the api answers, this engine delegates to proxmox_network.show_sdn_with_api.to.jsons.sh"
  echo "  (1 GET for the vnets, 1 per vnet for its subnets). The live SNAT rules are NOT api objects,"
  echo "  so both paths read them through proxmox_network.datacenter.list_snat_rules.to.jsons.sh, over"
  echo "  SSH. RANGE42_PROXMOX_API_FORCE=off keeps the ansible path, which composes the three cluster"
  echo "  readers. The same FIELDS on both paths, only source differs ; the join itself lives once,"
  echo "  in proxmox__inc.show_sdn.join.sh, so the two paths cannot disagree on a verdict."
  echo ""
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the context guard runs first : both paths read the vault through the same link
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

# the request is read once here (options, stdin or manifest), then handed to whichever path runs
REQ=$(proxmox__inc.show_sdn.request.sh "$@")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# auto-delegate to the direct API fast path when reachable
# override with RANGE42_PROXMOX_API_FORCE=off to keep the ansible slow path
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ "${RANGE42_PROXMOX_API_FORCE:-auto}" != "off" ]]; then
  if proxmox__inc.api_reachable.sh ; then
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "proxmox API reachable - delegating to proxmox_network.show_sdn_with_api.to.jsons.sh"
    exec proxmox_network.show_sdn_with_api.to.jsons.sh --request "$REQ"
  else
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "proxmox API not reachable - using ansible slow path"
  fi
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the ansible slow path : the three cluster readers, composed. A reader prints nothing at all when
# what it read holds nothing, so an empty output and a failure are told apart by the return code,
# never by the silence.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT=$(printf '%s' "$REQ" | jq -r '.output')

_lines() { jq -c 'if type == "array" then .[] else . end' ; }

_json_only() {
  local l
  while IFS= read -r l ; do
    [ -n "${l//[[:space:]]/}" ] || continue
    printf '%s\n' "$l" | jq -e . >/dev/null 2>&1 && printf '%s\n' "$l"
  done
  return 0
}

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

_read() { # $1 = the devkit to call, $2 = its stdin json ; prints its json lines, rc of the devkit
  local devkit="$1" payload="$2"
  set +e
  printf '%s\n' "$payload" | "$devkit" --json > "$TMP_DIR/raw" 2>/dev/null
  local rc=$?
  set -e
  _json_only < "$TMP_DIR/raw" | _lines
  return $rc
}

## the declaration : without it there is nothing to report on
VNETS_RAW=$(_read proxmox_network.datacenter.list_sdn_vnets.to.jsons.sh '{}') || {
  devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot read the sdn vnets of the cluster : nothing to report on" ; exit 1 ; }
SUBNETS_RAW=$(_read proxmox_network.datacenter.list_sdn_subnets.to.jsons.sh '{}') || {
  devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot read the sdn subnets of the cluster : nothing to report on" ; exit 1 ; }

## the live state, over SSH : a failure here does not end the run, it makes the counts unknown
set +e
RULES_RAW=$(_read proxmox_network.datacenter.list_snat_rules.to.jsons.sh '{}')
rc=$?
set -e
RULES_OK=true
if [[ "$rc" -ne 0 ]]; then
  RULES_OK=false
  devkit_utils.text.echo_trace.to.text.to.stderr.sh "cannot read the live SNAT rules of the node (rc ${rc}) : the counts stay unknown"
fi

printf '%s\n' "$VNETS_RAW"   > "$TMP_DIR/vnets.jsonl"
printf '%s\n' "$SUBNETS_RAW" > "$TMP_DIR/subnets.jsonl"
printf '%s\n' "$RULES_RAW"   > "$TMP_DIR/rules.jsonl"

NODE=$(printf '%s\n%s\n%s\n' "$VNETS_RAW" "$SUBNETS_RAW" "$RULES_RAW" \
  | jq -r 'select(type == "object" and .proxmox_node != null) | .proxmox_node' 2>/dev/null | head -1)

proxmox__inc.show_sdn.join.sh \
  "$TMP_DIR/vnets.jsonl" "$TMP_DIR/subnets.jsonl" "$TMP_DIR/rules.jsonl" \
  "$REQ" "$SOURCE_TAG" "$NODE" "$RULES_OK" > "$TMP_DIR/lines"

if [[ "$RULES_OK" != true ]]; then
  jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" \
    --arg reason "the live SNAT rules reader failed (rc ${rc})" \
    '
    {
      level: "error",
      action: $action,
      source: $src,
      proxmox_node: $node,
      vnet: null,
      reason: $reason
    }' >> "$TMP_DIR/lines"
fi

# the table is titled with the perimeter that was ASKED : a network the sdn does not declare still
# gets a row, so the rows alone do not say what was asked for
LABEL=$(printf '%s' "$REQ" | jq -r '
  if .scope == "scenario" then
    "scenario: " + (.scenario_name // "?")
  elif .scope == "sdn_vnet" then
    (.networks[0].vnet)
  elif .scope == "sdn_vnets" then
    ((.networks | length | tostring) + " networks on stdin")
  else
    "datacenter : every network"
  end')

proxmox__inc.show_sdn.render.sh "$OUTPUT" "$LABEL" < "$TMP_DIR/lines"
