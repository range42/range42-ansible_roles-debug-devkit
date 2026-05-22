#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

show_example() {

  echo "  $(basename "$0") /path/to/some/caller_script.sh team"
  echo "  $(basename "$0") \"\$0\" \"admin\""

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ] || [ $# -lt 2 ]; then
  echo
  echo
  echo NAME
  echo "  $(basename "$0") - list IPs of all VMs matching a role in the closest scenario manifest"
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help]"
  echo "  $(basename "$0") <caller_path> <role>"
  echo
  echo DESCRIPTION
  echo
  echo "  Walks up from <caller_path> until it finds a manifest/scenario_vms.json,"
  echo "  then outputs one IP per line for every VM whose role matches <role>."
  echo "  Output format: '<ip> # <vm_name>' so callers can echo or strip the suffix."
  echo "  Exits 1 if the manifest is not found. Outputs nothing (exit 0) if no VM"
  echo "  matches the role."
  echo
  echo EXAMPLES
  echo
  show_example
  echo
  echo
  exit 1
fi

caller_path="$1"
role="$2"

start_dir="$(cd "$(dirname "$caller_path")" 2>/dev/null && pwd)" || {
  devkit_utils.text.echo_error.to.text.to.stderr.sh "invalid caller_path: $caller_path"
  exit 1
}

d="$start_dir"
while [ "$d" != "/" ] && [ ! -f "$d/manifest/scenario_vms.json" ]; do
  d="$(dirname "$d")"
done

manifest="$d/manifest/scenario_vms.json"
if [ ! -f "$manifest" ]; then
  devkit_utils.text.echo_error.to.text.to.stderr.sh "scenario_vms.json not found walking up from $start_dir"
  exit 1
fi

jq -r --arg r "$role" '.vms[] | select(.role == $r) | "\(.ip) # \(.vm_name)"' "$manifest"
