#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# List the LIVE SNAT rules of the hypervisor, grouped by source network.
#
# Read only. The write side of the same subject is
# proxmox_network.sdn_subnet_cidr.delete_extra_snat_rules.to.jsons.sh, and the two are
# meant to be used together : this one shows the drift, that one normalises it.
#
# WHAT IT ANSWERS that no API read can : these rules are not API objects. They come from a
# post-up hook in /etc/network/interfaces.d, so the firewall endpoints - which only ever
# write the PVEFW-* chains - cannot see them. Until now nothing could read the live side
# without changing it.
#
# THE TARGET COLUMN IS THE POINT. Proxmox writes SNAT --to-source from a vnet's post-up
# hook ; the legacy bridge hack writes MASQUERADE from a vmbr stanza. Same effect on
# traffic, but only the first disappears when the SDN subnet goes to snat=0 - so a
# MASQUERADE here means the rule will come back at the next ifreload, whatever the SDN
# says. A count above 1 on a single source means an apply ran more than once : ifreload
# replays post-up without ever playing post-down.
#
# The rules live on the NODE, so the action reaches it through the proxmox_cli group over
# SSH. It takes no required input : proxmox_node is only the Ansible play target and is
# resolved from the vault when nothing is piped in. Pass a node name on STDIN to run the
# query through a specific node.
#
# The OUT INTERFACE is reported too, as snat_out_iface. Proxmox auto-detects it from the default
# route when it writes the vnet post-up hook, so no declaration holds it : this read is the only
# place it can be seen.
#
# The optional filter applies to the source network as iptables renders it, mask included,
# so 192.168.143 matches 192.168.143.0/24. To filter by target instead, pipe into jq on
# .snat_target.
#
set -euo pipefail
ACTION="network_list_snat_rules"
DEFAULT_OUTPUT_JSON=true
ARG_SNAT_SOURCE_FILTER=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITHOUT ANY INPUT (proxmox_node resolved from the vault) "
  echo
  echo "    $(basename "$0") "
  echo "    $(basename "$0") --json"
  echo "    $(basename "$0") --text"
  echo

  echo "  :: WITH A CASE INSENSITIVE FILTER ON THE SOURCE NETWORK "
  echo
  echo "    $(basename "$0") 192.168.143"
  echo "    $(basename "$0") 192.168.143.0/24 --json"
  echo

  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"px-testing\" | $(basename "$0") "
  echo "    echo \"px-testing\" | $(basename "$0") --json"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    '{"proxmox_node":"px-testing"}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --json"

  echo ""
  echo "  :: PIPING "
  echo
  echo "    $(basename "$0") | jq -r '.snat_source'"
  echo "    $(basename "$0") | jq -c 'select(.snat_target==\"MASQUERADE\")'      # the legacy hack rules"
  echo "    $(basename "$0") | jq -c 'select(.snat_count > 1)'                   # subnets an apply duplicated"
  echo "    $(basename "$0") | jq -r '\(.snat_source) leaves through \(.snat_out_iface)'  # the egress device"
  echo "    $(basename "$0") | jq -r 'select(.snat_source==\"192.168.143.0/24\") | .snat_count'"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - list the LIVE SNAT rules of the node - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo "  $(basename "$0")                                        - list every live SNAT rule, grouped by source network "
  echo "  $(basename "$0") [--json]                               - force output as json "
  echo "  $(basename "$0") [partial_or_complete_source] [--json]  - Force output in JSON format with a case insensitive filter on the source network "
  echo "  $(basename "$0") [--text]                               - force output as text (debug purpose)"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# browse provided arugments :
#

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    OUTPUT_JSON=true
    shift
    ;;
  --text)
    OUTPUT_JSON=false
    shift
    ;;
  -*)
    devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
    show_example
    exit 1
    ;;
  *)
    if [[ -z "$ARG_SNAT_SOURCE_FILTER" ]]; then
      ARG_SNAT_SOURCE_FILTER="$1"
      shift
    else
      devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
      show_example
      exit 1
    fi
    ;;
  esac
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_node is the play target, NOT part of a URL : this action reads the node over
# SSH through the proxmox_cli group. Without STDIN the helper fills it from the vault.
#
JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::proxmox_node" "STR::action")
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r NODE_JSON; do

  if [[ "$OUTPUT_JSON" == true ]]; then # json mode.

    if [[ -n "$ARG_SNAT_SOURCE_FILTER" ]]; then # check if filter provided in argument

      printf '%s\n' "$NODE_JSON" |
        proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" |
        jq -c ".[]" |
        devkit_transform.jsons.key_field_greper.to.jsons.sh "snat_source" "$ARG_SNAT_SOURCE_FILTER"

    else # not filter in argument

      printf '%s\n' "$NODE_JSON" |
        proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" |
        jq ".[]"

    fi

  else # text output mode  - debug

    printf '%s\n' "$NODE_JSON" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
