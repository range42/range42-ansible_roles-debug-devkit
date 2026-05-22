#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

show_example() {

  echo "  $(basename "$0") /path/to/some/caller_script.sh bs2-admin-wazuh"
  echo "  $(basename "$0") \"\$0\" \"bs4-admin-wazuh\""

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ] || [ $# -lt 2 ]; then
  echo
  echo
  echo NAME
  echo "  $(basename "$0") - lookup IP of a VM in the closest scenario manifest"
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help]"
  echo "  $(basename "$0") <caller_path> <vm_name>"
  echo
  echo DESCRIPTION
  echo
  echo "  Walks up from <caller_path> until it finds a manifest/scenario_vms.json,"
  echo "  then outputs the ip of the VM whose vm_name matches <vm_name>."
  echo "  Exits 1 with an error on stderr if the manifest is not found or the"
  echo "  vm_name is not present in it."
  echo
  echo EXAMPLES
  echo
  show_example
  echo
  echo
  exit 1
fi

caller_path="$1"
vm_name="$2"

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

vm_ip=$(jq -r --arg n "$vm_name" '.vms[] | select(.vm_name == $n) | .ip' "$manifest")
if [ -z "$vm_ip" ] || [ "$vm_ip" = "null" ]; then
  devkit_utils.text.echo_error.to.text.to.stderr.sh "vm_name '$vm_name' not found in $manifest"
  exit 1
fi

echo "$vm_ip"
