#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

show_example() {

  echo "  $(basename "$0") /path/to/some/caller_script.sh vmbr142"
  echo "  $(basename "$0") \"\$0\" \"vmbr143\" | proxmox_vm.vm_id.stop.to.jsons.sh"

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ] || [ $# -lt 2 ]; then
  echo
  echo
  echo NAME
  echo "  $(basename "$0") - list full VM entries (JSON lines) on a given bridge"
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help]"
  echo "  $(basename "$0") <caller_path> <bridge>"
  echo
  echo DESCRIPTION
  echo
  echo "  Walks up from <caller_path> until it finds a manifest/scenario_vms.json,"
  echo "  then outputs one compact JSON object per line for every VM whose bridge"
  echo "  matches <bridge>. Output is jsons (newline-delimited JSON) compatible"
  echo "  with the rest of the devkit pipeline."
  echo "  Exits 1 if the manifest is not found. Outputs nothing (exit 0) if no VM"
  echo "  matches the bridge."
  echo
  echo EXAMPLES
  echo
  show_example
  echo
  echo
  exit 1
fi

caller_path="$1"
bridge="$2"

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

jq -c --arg b "$bridge" '.vms[] | select(.bridge == $b)' "$manifest"
