#!/bin/bash

#
# The anti-lockout of the DATACENTER, made callable.
#
# The action it wraps installs the two rules that keep every node reachable once a firewall
# goes on : one on the api port, one on ssh, both ABOVE the first inbound deny and both
# ACTIVE. It reads the chain before writing, so running it twice posts nothing the second
# time.
#
# WHY THE DATACENTER AND NOT THE NODE
# Proxmox applies the datacenter rules to every node's host chain. A guard placed here
# therefore covers a node that does not exist yet : a node added next month arrives
# protected, without anyone remembering to run anything on it. A per-node guard has to be
# replayed on every new node, and the one that is forgotten is the one that locks out.
# The node-level wrapper is kept and stays usable for an explicit per-node guard on top.
#
# WHY IT MATTERS THAT THIS WRAPPER EXISTS
# Enabling a firewall with no accepted path loses the web interface AND ssh at once, on the
# machine everything else is driven from, and recovery then needs console access. At this
# level it would happen on every node at the same time.
#
# Measured on a test node : a firewall enabled with zero rules is a deny, refused in both
# directions, the hypervisor included. So the guard is not a precaution, it is a
# precondition.
#
# AND MEASURED THE SAME DAY : the node-level guard used to post its two rules WITHOUT the
# enable field, so Proxmox stored them disabled - present in the configuration, absent from
# the compiled chain, granting nothing - while its own test could not tell, because the test
# did not look at that field either. Both rules here carry enable explicitly, and the test
# counts only rules that are actually active.
#
# WHAT IT REPORTS
# The action publishes what it FOUND as well as what was asked of it : `*_pos_requested`
# is the caller's parameter, `*_pos_before` is where the chain actually held that accept,
# and `first_deny_pos_before` is the barrier they are measured against. A value of 99999
# means there was no deny at all. Read the `_before` fields to know the state, never the
# `_requested` ones.
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_dc_enable_management_access"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"px-testing\" | $(basename "$0") "
  echo "    echo \"px-testing\" | $(basename "$0") --json"
  echo "    echo \"px-testing\" | $(basename "$0") --text"
  echo
  echo "    cat /tmp/proxmox_node.text | $(basename "$0")"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    \
    '{"proxmox_node":"px-testing"}'
    '{"proxmox_node":"px-testing", "dc_fw_api_port":"8006", "dc_fw_ssh_port":"22"}'
    '{"proxmox_node":"px-testing", "dc_fw_api_pos":0, "dc_fw_ssh_pos":1}'
    '{"proxmox_node":"px-testing", "dc_fw_mgmt_source":"192.168.0.0/16"}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[0]}")" "$(basename "$0") --json"

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Install the two rules that keep every node reachable - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                            $(basename "$0") [-h|--help] "
  echo "  STDIN :: [proxmox_node] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [proxmox_node] | $(basename "$0") [--text]    - force output as text"
  echo ""
  echo OPTIONAL FIELDS
  echo
  echo "  dc_fw_api_port      the api port to accept, 8006 when omitted"
  echo "  dc_fw_ssh_port      the ssh port to accept, 22 when omitted"
  echo "  dc_fw_api_pos       where to post the api accept, 0 when omitted"
  echo "  dc_fw_ssh_pos       where to post the ssh accept, 1 when omitted"
  echo "  dc_fw_mgmt_source   restrict both accepts to a source, unrestricted when omitted"
  echo "  dc_fw_api_comment   comment on the api rule"
  echo "  dc_fw_ssh_comment   comment on the ssh rule"
  echo ""
  echo "  The two positions default to the top of the chain, which is always safe : nothing"
  echo "  can sit above position 0, so an accept posted there lands above any deny. Giving"
  echo "  a higher position can place an accept BELOW a deny, where it grants nothing."
  echo ""
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh
proxmox__inc.warmup_checks_stdin.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# define output type
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

case "${1:-}" in
--json)
  OUTPUT_JSON=true
  ;;
--text)
  OUTPUT_JSON=false
  ;;
"") ;;
*)
  devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
  show_example
  exit 1
  ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# Only proxmox_node is required. The seven optional fields are already known to the
# shared normaliser, so they are declared here and nothing else had to change.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh \
  "STR::proxmox_node" \
  "STR::dc_fw_api_port" \
  "STR::dc_fw_ssh_port" \
  "STR::dc_fw_api_pos" \
  "STR::dc_fw_ssh_pos" \
  "STR::dc_fw_mgmt_source" \
  "STR::dc_fw_api_comment" \
  "STR::dc_fw_ssh_comment" \
  "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  if [[ "$OUTPUT_JSON" == true ]]; then

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION"

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
