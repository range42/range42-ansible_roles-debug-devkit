#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# devkit_utils.jsons.render.to.table.sh
#
# Render JSON lines read on stdin as an aligned text table. A pure pipe : it reads no vault,
# calls no api and needs no workspace, so any devkit output becomes readable without touching
# the devkit itself. One positional argument per column, in the wanted order : key:HEADER, or
# the key alone (the header is then the key in upper case), or key:HEADER:WIDTH to give the
# column a minimum width (stable columns from one run to the next). The key may be a dotted
# path (a.b).
#
# Cells : a null or absent key prints "-", true/false print yes/no, arrays are joined by ",",
# objects print as compact json, everything else prints as is. The width of a column follows
# its longest cell (or its minimum width), two spaces separate the columns, no trailing space.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

INDENT=2
WITH_HEADER=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: THE TABLE OF THE FIREWALL VIEW (one row per network card)"
  echo
  echo "    proxmox_firewall.scenario.show_firewall.to.jsons.sh | jq -c 'select(.level == \"card\")' \\"
  echo "      | $(basename "$0") vm_id:VM_ID vm_name:VM_NAME guest_enable:GUEST vm_network_device:CARD vm_network_bridge:BRIDGE card_firewall_flag:FLAG effectively_filtered:FILTERED"
  echo
  echo "  :: KEYS ALONE, THE HEADERS ARE THE KEYS IN UPPER CASE"
  echo
  echo "    proxmox_vm.list.to.jsons.sh | $(basename "$0") vm_id vm_name vm_status"
  echo
  echo "  :: RENAME A COLUMN, REACH A NESTED KEY, CHANGE THE INDENT"
  echo
  echo "    proxmox_vm.list.to.jsons.sh | $(basename "$0") vm_id:ID vm_meta.cpu_allocated:CPUS --indent 4"
  echo
  echo "  :: GIVE A COLUMN A MINIMUM WIDTH, SO THE TABLE KEEPS ITS SHAPE FROM ONE RUN TO THE NEXT"
  echo
  echo "    proxmox_vm.list.to.jsons.sh | $(basename "$0") vm_id:VM_ID:5 vm_name:VM_NAME:25 vm_status:STATUS"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - render JSON lines as an aligned text table "
  echo
  echo OPTIONS
  echo
  echo "                      $(basename "$0") [-h|--help]"
  echo "  STDIN :: [jsons] | $(basename "$0") [--indent N] [--no-header] <key:HEADER[:WIDTH]|key> [<key:HEADER[:WIDTH]|key> ...]"
  echo
  echo "  --indent N         spaces before each line (default 2)"
  echo "  --no-header        rows only"
  echo "  key:HEADER         one column : the json key (a dotted path is allowed) and the text of its header"
  echo "  key:HEADER:WIDTH   the same, with a minimum width for the column"
  echo "  key                one column, header = the key in upper case"
  echo
  echo CELLS
  echo
  echo "  null or absent -> -      true / false -> yes / no      array -> a,b,c      object -> compact json"
  echo "  A line that is not json is skipped with a trace on stderr. A json array is unfolded, one row per element."
  echo "  No row : the header alone (nothing with --no-header), exit 0. No column : this help, exit 1."
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# arguments : options first or anywhere, then the column specifications
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

SPECS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --indent)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh "--indent needs a number." ; exit 1 ; }
    INDENT="$2"
    shift 2
    ;;
  --no-header)
    WITH_HEADER=false
    shift
    ;;
  -*)
    devkit_utils.text.echo_error.to.text.to.stderr.sh "unknown option : $1"
    show_example
    exit 1
    ;;
  *)
    [[ "$1" != ":"* ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh "a column needs a key before the colon : $1" ; exit 1 ; }
    SPECS+=("$1")
    shift
    ;;
  esac
done

if [ "${#SPECS[@]}" -eq 0 ]; then
  devkit_utils.text.echo_error.to.text.to.stderr.sh "no column given : name at least one key or key:HEADER."
  show_example
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  devkit_utils.text.echo_error.to.text.to.stderr.sh "jq is not installed"
  exit 2
fi

# [{key, header, width}] in the order given ; the header is free text, so it may itself hold a
# colon : a LAST segment made of digits, after a header, is the minimum width of the column
COLS_JSON=$(printf '%s\n' "${SPECS[@]}" | jq -R -c '
  split(":") as $p
  | if ($p | length) >= 3 and ($p[-1] | test("^[0-9]+$")) then { key: $p[0], header: ($p[1:-1] | join(":")), width: ($p[-1] | tonumber) }
    elif ($p | length) >= 2 then { key: $p[0], header: ($p[1:] | join(":")), width: 0 }
    else { key: ., header: ascii_upcase, width: 0 } end' | jq -s -c .)

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# rows : keep the lines that ARE json, unfold arrays, then one tab-separated row per object
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

_json_lines() {
  local l
  while IFS= read -r l; do
    [ -n "${l//[[:space:]]/}" ] || continue
    if printf '%s\n' "$l" | jq -e . >/dev/null 2>&1; then
      printf '%s\n' "$l" | jq -c 'if type == "array" then .[] else . end'
    else
      devkit_utils.text.echo_trace.to.text.to.stderr.sh "skipped a line that is not json"
    fi
  done
  return 0
}

ROWS=$(_json_lines | jq -r --argjson cols "$COLS_JSON" '
  def cell:
    if . == null then "-"
    elif type == "boolean" then (if . then "yes" else "no" end)
    elif type == "array" then (map(if type == "string" then . else tojson end) | join(","))
    elif type == "object" then tojson
    else (tostring | gsub("[\t\n\r]"; " ")) end;
  select(type == "object") as $o
  | [ $cols[] | (.key | split(".")) as $p | ($o | getpath($p)) | cell ]
  | join("\t")')

HEADER=$(printf '%s\n' "$COLS_JSON" | jq -r 'map(.header) | join("\t")')
MIN_WIDTHS=$(printf '%s\n' "$COLS_JSON" | jq -r 'map(.width | tostring) | join("\t")')

{
  if [[ "$WITH_HEADER" == true ]]; then printf '%s\n' "$HEADER"; fi
  if [ -n "$ROWS" ]; then printf '%s\n' "$ROWS"; fi
} | awk -F'\t' -v indent="$INDENT" -v minw="$MIN_WIDTHS" '
  BEGIN { n = split(minw, mw, "\t") ; for (i = 1; i <= n; i++) w[i] = mw[i] + 0 ; nf = n }
  {
    if (NF > nf) nf = NF
    for (i = 1; i <= NF; i++) { row[NR, i] = $i ; l = length($i) ; if (l > w[i]) w[i] = l }
    nr = NR
  }
  END {
    pad = sprintf("%*s", indent, "")
    for (r = 1; r <= nr; r++) {
      line = pad
      for (i = 1; i <= nf; i++) {
        c = row[r, i]
        if (i < nf) line = line sprintf("%-*s", w[i] + 2, c) ; else line = line c
      }
      print line
    }
  }'
