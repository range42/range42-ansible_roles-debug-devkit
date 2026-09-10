#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox__inc.show_firewall_rules.render.sh json|text|table
#
# Shared by the show_firewall_rules engine and its _with_api twin : reads the json lines of the
# view on stdin (levels dc_rule, node_rule, guest_rule, guest, absent, error) and prints them in
# the asked form.
#
#   json    the lines as they are
#           (the verdict stays two arrays here : in_force_on and why_not)
#   text    one line of words per json line
#   table   three tables, one per level of the firewall, through the shared renderer, then the
#           guests without a rule, the ids the node does not run, the unreadable ones
#
# THREE LEVELS, THREE PREFIXES. A rule of the datacenter carries dc_fw_*, one of the node
# node_fw_*, one of a guest vm_fw_*, the names the reading actions have always published. So the
# table asks for three column sets rather than renaming anything.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - shared renderer of the show_firewall_rules engine and its twin "
  echo
  echo OPTIONS
  echo
  echo "  STDIN :: jsons | $(basename "$0") json|text|table [<guests label>]"
  echo
  echo "  <guests label>   what the guest table covers, as the caller ASKED it (a scenario name, the"
  echo "                   node, an id) ; the engines build it from the scope of the request. Without"
  echo "                   it the table keeps its bare title."
  echo
  echo
  exit 1
fi

MODE="${1:-json}"
# the title of the guest table says the perimeter that was ASKED. Without it a reader takes the rows
# for the whole perimeter, when a guest with an empty chain is only reported in the line below.
GUESTS_LABEL="${2:-}"
case "$MODE" in
json | text | table) ;;
*)
  devkit_utils.text.echo_error.to.text.to.stderr.sh " unknown output : ${MODE} (json, text or table)"
  exit 1
  ;;
esac

# NOT "LINES" : bash and zsh own that name (the terminal height) and rewrite it after every
# external command when a terminal is attached.
VIEW_JSON=$(cat)

if [[ "$MODE" == "json" ]]; then
  [ -n "$VIEW_JSON" ] && printf '%s\n' "$VIEW_JSON"
  exit 0
fi

if [[ "$MODE" == "text" ]]; then
  [ -n "$VIEW_JSON" ] && printf '%s\n' "$VIEW_JSON" | jq -r '
    def cell($v): ($v // "-") | tostring;
    ## the cards a rule is in force on, or a dash AND the named cause : never a bare no
    def in_force:
      if ((.vm_fw_in_force_on // []) | length) > 0 then (.vm_fw_in_force_on | join(","))
      elif ((.vm_fw_why_not // []) | length) > 0 then ("- " + (.vm_fw_why_not | join(",")))
      else "-" end;
    if .level == "dc_rule" then
      "datacenter  pos \(cell(.dc_fw_pos))  \(cell(.dc_fw_action))  \(cell(.dc_fw_type))  proto=\(cell(.dc_fw_proto))  dport=\(cell(.dc_fw_dport))  source=\(cell(.dc_fw_source))  enable=\(cell(.dc_fw_enable))  \(cell(.dc_fw_comment))"
    elif .level == "node_rule" then
      "node \(.proxmox_node)  pos \(cell(.node_fw_pos))  \(cell(.node_fw_action))  \(cell(.node_fw_type))  proto=\(cell(.node_fw_proto))  dport=\(cell(.node_fw_dport))  source=\(cell(.node_fw_source))  enable=\(cell(.node_fw_enable))  \(cell(.node_fw_comment))"
    elif .level == "guest_rule" then
      "vm \(.vm_id) (\(cell(.vm_name)))  pos \(cell(.vm_fw_pos))  \(cell(.vm_fw_action))  \(cell(.vm_fw_type))  proto=\(cell(.vm_fw_proto))  dport=\(cell(.vm_fw_dport))  source=\(cell(.vm_fw_source))  enable=\(cell(.vm_fw_enable))  \(cell(.vm_fw_comment))  in_force=\(in_force)"
    elif .level == "guest" then
      "vm \(.vm_id) (\(cell(.vm_name))) : no rule in its chain"
    elif .level == "absent" then
      "vm \(.vm_id) : not on this node"
    elif .level == "error" then
      "vm \(.vm_id) : unreadable (\(.reason))"
    else tojson end'
  exit 0
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# table : one per level, and only for the levels that carry a rule
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

[ -n "$VIEW_JSON" ] || exit 0

_table() { # $1 = level, $2 = prefix, $3.. = the columns of the renderer
  local level="$1" ; shift
  local rows
  rows=$(printf '%s\n' "$VIEW_JSON" | jq -c --arg l "$level" 'select(.level == $l)')
  [ -n "$rows" ] || return 0
  printf '%s\n' "$rows" | devkit_utils.jsons.render.to.table.sh "$@"
  echo ""
}

DC=$(printf '%s\n' "$VIEW_JSON" | jq -c 'select(.level == "dc_rule")')
if [ -n "$DC" ]; then
  echo "  datacenter"
  _table dc_rule dc_fw_pos:POS:4 dc_fw_action:ACTION:8 dc_fw_type:TYPE:6 dc_fw_proto:PROTO:6 dc_fw_dport:DPORT:6 dc_fw_source:SOURCE:16 dc_fw_enable:ON:3 dc_fw_comment:COMMENT
else
  printf '  datacenter : no rule\n\n'
fi

ND=$(printf '%s\n' "$VIEW_JSON" | jq -c 'select(.level == "node_rule")')
NODE_NAME=$(printf '%s\n' "$VIEW_JSON" | jq -r 'select(.proxmox_node != null) | .proxmox_node' | head -1)
if [ -n "$ND" ]; then
  echo "  node ${NODE_NAME}"
  _table node_rule node_fw_pos:POS:4 node_fw_action:ACTION:8 node_fw_type:TYPE:6 node_fw_proto:PROTO:6 node_fw_dport:DPORT:6 node_fw_source:SOURCE:16 node_fw_enable:ON:3 node_fw_comment:COMMENT
else
  printf '  node %s : no rule\n\n' "$NODE_NAME"
fi

GU=$(printf '%s\n' "$VIEW_JSON" | jq -c 'select(.level == "guest_rule")')
if [ -n "$GU" ]; then
  if [[ -n "$GUESTS_LABEL" ]]; then echo "  guests  (${GUESTS_LABEL})" ; else echo "  guests" ; fi
  ## the verdict is a derived cell, not a field of the view : the json lines keep their two arrays
  printf '%s\n' "$GU" \
    | jq -c '
        . + { vm_fw_in_force_text:
                ( if ((.vm_fw_in_force_on // []) | length) > 0 then (.vm_fw_in_force_on | join(","))
                  elif ((.vm_fw_why_not // []) | length) > 0 then ("- " + (.vm_fw_why_not | join(",")))
                  else "-" end ) }' \
    | devkit_utils.jsons.render.to.table.sh vm_id:VM_ID:5 vm_name:VM_NAME:25 vm_fw_pos:POS:4 vm_fw_action:ACTION:8 vm_fw_type:TYPE:6 vm_fw_proto:PROTO:6 vm_fw_dport:DPORT:6 vm_fw_source:SOURCE:16 vm_fw_enable:ON:3 "vm_fw_in_force_text:IN FORCE ON:11" vm_fw_comment:COMMENT
  echo ""
fi

NO_RULE=$(printf '%s\n' "$VIEW_JSON" | jq -r 'select(.level == "guest") | .vm_id' | paste -sd ' ' -)
ABSENT=$(printf '%s\n' "$VIEW_JSON" | jq -r 'select(.level == "absent") | .vm_id' | paste -sd ' ' -)
ERRORS=$(printf '%s\n' "$VIEW_JSON" | jq -r 'select(.level == "error") | "  unreadable : vm \(.vm_id) (\(.reason))"')

[ -z "$NO_RULE" ] || printf '  no rule in the chain : %s\n\n' "$NO_RULE"
[ -z "$ABSENT" ] || printf '  not on this node : %s\n\n' "$ABSENT"
[ -z "$ERRORS" ] || printf '%s\n\n' "$ERRORS"
