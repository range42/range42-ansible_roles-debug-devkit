#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox__inc.show_firewall.request.sh
#
# SHARED BY THE WHOLE show_* FAMILY, not only by the view its name comes from : it knows nothing
# about the firewall, it reads a scope, an output and a set of guest ids. show_firewall and its
# twin were the first callers, show_firewall_rules and its twin are the next ; the name is kept as
# it is so the two commits that use it stay small, and this paragraph is the warning that the name
# says less than the file does.
#
# Reads the options and the input ONCE, validates them, and prints one json line describing the
# request :
#
#   {"scope":"vm_ids","output":"table","ids":[2001,2002],"stdin_nodes":[]}
#
# scope   vm_id | vm_ids | scenario | node | dc | all
#         without --scope : a positional id means vm_id, ids on stdin mean vm_ids, no stdin
#         means scenario (the vms of the active scenario, read in the workspace manifest)
# output  json (default) | text | table
# ids     the guests to read, in the order given, duplicates folded ; null for node, dc, all
#         (every guest the node runs)
#
# Exit 1 with a message on stderr when the request cannot be honoured : two scopes, an
# unknown scope, a line that is not a vm_id, vm_id with more than one id, vm_ids without
# stdin, scenario without a manifest.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - shared request parser of the show_firewall engine and its twin "
  echo
  echo OPTIONS
  echo
  echo "  [STDIN :: ids] | $(basename "$0") [--scope vm_id|vm_ids|scenario|node|dc|all] [--json|--text|--table] [vm_id]"
  echo
  echo "  prints one json line : {scope, output, ids, stdin_nodes}"
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
POS_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --scope)
    [[ -n "${2:-}" ]] || _fail "--scope needs a value : vm_id, vm_ids, scenario, node, dc or all"
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
    [[ "$1" =~ ^[0-9]+$ ]] || _fail "not a vm_id : $1"
    [[ -z "$POS_ID" ]] || _fail "only one vm_id may be given as an argument : pipe several ids on stdin"
    POS_ID="$1"
    shift
    ;;
  esac
done

case "$SCOPE" in
"" | vm_id | vm_ids | scenario | node | dc | all) ;;
*) _fail "unknown scope : ${SCOPE} (vm_id, vm_ids, scenario, node, dc or all)" ;;
esac

if [[ -z "$SCOPE" ]]; then
  if [[ -n "$POS_ID" ]]; then SCOPE="vm_id"
  elif [[ ! -t 0 ]]; then SCOPE="vm_ids"
  else SCOPE="scenario"; fi
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# the ids of the request, by scope
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

IDS_JSON="null"
STDIN_NODES_JSON="[]"

_read_stdin_ids() {
  # plain ids or json objects carrying vm_id (and maybe proxmox_node, collected for a trace)
  local l parsed
  [[ ! -t 0 ]] || _fail "no input on stdin : pipe the vm ids (one per line, plain or json)"
  parsed=$(while IFS= read -r l; do
    [ -n "${l//[[:space:]]/}" ] || continue
    if [[ "$l" =~ ^[[:space:]]*[0-9]+[[:space:]]*$ ]]; then
      printf '{"vm_id":%s}\n' "$(printf '%s' "$l" | tr -d '[:space:]')"
    elif printf '%s\n' "$l" | jq -e 'type == "object" and (.vm_id | type) == "number"' >/dev/null 2>&1; then
      printf '%s\n' "$l" | jq -c '{vm_id: .vm_id, proxmox_node: (.proxmox_node // null)}'
    elif printf '%s\n' "$l" | jq -e 'type == "object" and (.vm_id | type) == "string" and (.vm_id | test("^[0-9]+$"))' >/dev/null 2>&1; then
      printf '%s\n' "$l" | jq -c '{vm_id: (.vm_id | tonumber), proxmox_node: (.proxmox_node // null)}'
    else
      printf '{"bad_line":%s}\n' "$(printf '%s' "$l" | jq -R -c .)"
    fi
  done)
  local bad
  bad=$(printf '%s\n' "$parsed" | jq -r -s 'map(select(.bad_line != null)) | .[0].bad_line // empty')
  [[ -z "$bad" ]] || _fail "cannot read a vm_id from this line : ${bad}"
  IDS_JSON=$(printf '%s\n' "$parsed" | jq -s -c '
    [ .[].vm_id ]
    | reduce .[] as $x ([]; if index($x) == null then . + [$x] else . end)')
  STDIN_NODES_JSON=$(printf '%s\n' "$parsed" | jq -s -c '[.[].proxmox_node | select(. != null)] | unique')
}

case "$SCOPE" in
vm_id)
  if [[ -n "$POS_ID" ]]; then
    IDS_JSON="[${POS_ID}]"
  else
    _read_stdin_ids
    n=$(printf '%s' "$IDS_JSON" | jq 'length')
    [[ "$n" -eq 1 ]] || _fail "vm_id takes exactly one id, got ${n} : use --scope vm_ids for a set"
  fi
  ;;
vm_ids)
  if [[ -n "$POS_ID" ]]; then
    IDS_JSON="[${POS_ID}]"
  else
    _read_stdin_ids
    [[ "$(printf '%s' "$IDS_JSON" | jq 'length')" -gt 0 ]] || _fail "no vm_id read on stdin : pipe one id per line, or ask for a scope (--scope scenario, node, dc, all)"
  fi
  ;;
scenario)
  [[ -n "${RANGE42_ACTIVE_CONFIG_DIR:-}" ]] || _fail "no active workspace in this shell (RANGE42_ACTIVE_CONFIG_DIR is empty) - run : range42-context use <codename> <scenario>"
  MANIFEST="${RANGE42_ACTIVE_CONFIG_DIR%/}/scenario/manifest/scenario_vms.json"
  [[ -f "$MANIFEST" ]] || _fail "the active scenario has no manifest : ${MANIFEST}"
  IDS_JSON=$(jq -c '
    [ .vms[].vm_id | tonumber ]
    | reduce .[] as $x ([]; if index($x) == null then . + [$x] else . end)' "$MANIFEST" 2>/dev/null) || _fail "cannot read the vm ids of the manifest : ${MANIFEST}"
  [[ "$(printf '%s' "$IDS_JSON" | jq 'length')" -gt 0 ]] || _fail "the manifest declares no vm : ${MANIFEST}"
  # the name travels with the request : the renderers title their guest table with the perimeter
  # that was ASKED, not with what happens to have a rule today
  SCENARIO_NAME=$(jq -r '.scenario // empty' "$MANIFEST" 2>/dev/null || true)
  ;;
node | dc | all)
  IDS_JSON="null"
  ;;
esac

jq -n -c --arg scope "$SCOPE" --arg output "$OUTPUT" --argjson ids "$IDS_JSON" --argjson nodes "$STDIN_NODES_JSON" \
  --arg scenario_name "${SCENARIO_NAME:-}" \
  '
  {
    scope: $scope,
    output: $output,
    ids: $ids,
    stdin_nodes: $nodes,
    scenario_name: (if $scenario_name == "" then null else $scenario_name end)
  }'
