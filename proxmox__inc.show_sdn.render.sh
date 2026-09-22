#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox__inc.show_sdn.render.sh json|text|table [<perimeter label>]
#
# Shared by the show_sdn engine and its _with_api twin : reads the json lines of the view on stdin
# (levels network, undeclared, rules_only, error) and prints them in the asked form.
#
#   json    the lines as they are
#   text    one line of words per json line
#   table   one row per network through the shared renderer, then the networks the SDN does not
#           declare, then the live rules no declared network accounts for, then the errors
#
# THE TABLE IS TITLED WITH THE PERIMETER THAT WAS ASKED. A network whose SDN declaration is absent
# still gets a row - a legacy vmbr bridge is exactly that - so the rows alone do not say what was
# asked for. The engines build the label from the scope of the request.
#
# The two views of range42-context add the columns a manifest holds, the roles and the scope
# labels, which no api and no node knows : they render their own table from these json lines.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - shared renderer of the show_sdn engine and its twin "
  echo
  echo OPTIONS
  echo
  echo "  STDIN :: jsons | $(basename "$0") json|text|table [<perimeter label>]"
  echo
  echo "  <perimeter label>   what the table covers, as the caller ASKED it (a scenario name, the"
  echo "                      datacenter, a network) ; without it the table has no title line"
  echo
  echo
  exit 1
fi

MODE="${1:-json}"
LABEL="${2:-}"
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
    def flag($v): (if $v then "yes" else "no" end);
    if .level == "network" then
      "\(.vnet) (\(cell(.cidr)))  zone=\(cell(.zone))  outgoing_nat=\(.outgoing_nat)  rules=\(cell(.snat_rules))  origin=\(cell(.snat_origin))  out=\(cell(.snat_out_iface | if . == null then null else join(",") end))  isolated=\(flag(.isolated))  internet=\(.internet)"
    elif .level == "undeclared" then
      "\(.vnet) (\(cell(.cidr)))  not declared in the sdn  rules=\(cell(.snat_rules))  origin=\(cell(.snat_origin))  internet=\(.internet)"
    elif .level == "rules_only" then
      "\(cell(.cidr)) : live rules no declared network accounts for  rules=\(cell(.snat_rules))  origin=\(cell(.snat_origin))"
    elif .level == "error" then
      "\(cell(.vnet)) : unreadable (\(.reason))"
    else tojson end'
  exit 0
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# table
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

[ -n "$VIEW_JSON" ] || exit 0

[ -z "$LABEL" ] || echo "  sdn state  (${LABEL})"

ROWS=$(printf '%s\n' "$VIEW_JSON" | jq -c 'select(.level == "network" or .level == "undeclared")')
if [ -n "$ROWS" ]; then
  ## the out interfaces are a derived cell : the json line keeps its array
  printf '%s\n' "$ROWS" \
    | jq -c '
        . + { snat_out_text:
                ( if ((.snat_out_iface // []) | length) > 0 then (.snat_out_iface | join(","))
                  else null end ) }' \
    | devkit_utils.jsons.render.to.table.sh vnet:VNET:9 cidr:CIDR:19 zone:ZONE:9 \
        "outgoing_nat:OUTGOING NAT:12" "snat_rules:NAT RULES:9" snat_origin:ORIGIN:7 \
        snat_out_text:OUT:7 isolated:ISOLATED:8 internet:INTERNET
  echo ""
else
  printf '  no network in this perimeter\n\n'
fi

UNDECLARED=$(printf '%s\n' "$VIEW_JSON" | jq -r 'select(.level == "undeclared") | .vnet' | paste -sd ' ' -)
ORPHAN=$(printf '%s\n' "$VIEW_JSON" | jq -r 'select(.level == "rules_only") | "  live rules no declared network accounts for : \(.cidr) (\(.snat_rules))"')
ERRORS=$(printf '%s\n' "$VIEW_JSON" | jq -r 'select(.level == "error") | "  unreadable : \(.vnet // "-") (\(.reason))"')

[ -z "$UNDECLARED" ] || printf '  not declared in the sdn : %s\n\n' "$UNDECLARED"
[ -z "$ORPHAN" ] || printf '%s\n\n' "$ORPHAN"
[ -z "$ERRORS" ] || printf '%s\n\n' "$ERRORS"
