#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox_network.datacenter.list_snat_rules_with_ssh.to.jsons.sh
# Direct ssh variant of proxmox_network.datacenter.list_snat_rules.to.jsons.sh
#
# The role action network_list_snat_rules is a shell block run on the hypervisor through
# the proxmox_cli group : there is no api for iptables. This twin runs THE SAME block on
# THE SAME host, without the ansible play around it : proxmox__inc.snat_rules.node.sh is
# copied to the node, run there (`list`), and removed, in one ssh session.
#
# Same output lines as the role : one per (source network, out interface, target), with
# snat_count ; `snat_host` is the inventory name of the node ; only `source` differs.
# The optional argument filters on snat_source, as the facade does.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="network_list_snat_rules"
SOURCE_TAG="proxmox-ssh"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITHOUT STDIN : the node of the vault"
  echo
  echo "    $(basename "$0")"
  echo "    $(basename "$0") --json | jq -r '[.snat_source, (.snat_count|tostring)] | @tsv'"
  echo "    $(basename "$0") 192.168.143         # only the sources matching this filter"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - list the LIVE SNAT rules of the hypervisor, grouped by source network - direct ssh run of the role's block ($ACTION)"
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help]"
  echo "  $(basename "$0") [--json] [snat_source filter]    - force output as json *default"
  echo "  $(basename "$0") [--text] [snat_source filter]    - force output as text"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"
FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_JSON=true ; shift ;;
    --text) OUTPUT_JSON=false ; shift ;;
    -*)
      echo "ERROR: unknown arg '$1'" >&2
      show_example >&2
      exit 1
      ;;
    *)
      if [[ -z "$FILTER" ]]; then FILTER="$1" ; shift ; else
        echo "ERROR: wrong number of arguments." >&2
        show_example >&2
        exit 1
      fi
      ;;
  esac
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# shared context guard : same refusals as the ansible path
proxmox__inc.warmup_checks.sh

# the node of the vault (for proxmox_node), then the hypervisor over ssh
source proxmox__inc.api_auth.sh
source proxmox__inc.ssh_node.sh

_trace() { devkit_utils.text.echo_trace.to.text.to.stderr.sh "$@" ; }
_error() { devkit_utils.text.echo_error.to.text.to.stderr.sh "$@" ; }
_emit()  { if [[ "$OUTPUT_JSON" == true ]]; then jq -c . ; else jq -r 'to_entries[] | "\(.key)=\(.value)"' ; fi ; }

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# without stdin the ansible path lists once for the node of the vault : same here
if [ -t 0 ]; then
  INPUT="$(printf '{"proxmox_node":"%s"}\n' "$NODE")"
else
  INPUT="$(cat -)"
  [[ -n "$INPUT" ]] || INPUT="$(printf '{"proxmox_node":"%s"}\n' "$NODE")"
fi

# a here-string, not a pipe : an exit inside the loop must end the script, not a subshell
while IFS= read -r LINE ; do
  [[ -z "$LINE" ]] && continue

  REQ="$(printf '%s' "$LINE" | jq -cR '(fromjson? // .) as $v | if ($v | type) == "object" then $v else {proxmox_node: $v} end' 2>/dev/null || echo '{}')"
  LINE_NODE="$(printf '%s' "$REQ" | jq -r '.proxmox_node // empty')"
  [[ -z "$LINE_NODE" || "$LINE_NODE" == "$NODE" ]] || _trace "proxmox_node ${LINE_NODE} given on stdin is ignored, the node comes from the vault : ${NODE}"

  _trace "reading the live nat table of ${SSH_HOST} over ssh"
  if ! _node_script_run list ; then
    _error "the node script did not complete on ${SSH_HOST} (rc ${NODE_RC}) : ${NODE_ERR}"
    exit 1
  fi
  RULES="$NODE_OUT"

  printf '%s\n' "$RULES" | jq -c \
    --arg action "$ACTION" \
    --arg source "$SOURCE_TAG" \
    --arg node "$NODE" \
    --arg host "$SSH_HOST" \
    '{
      action: $action,
      source: $source,
      proxmox_node: $node,
      snat_host: $host,
      snat_source: .snat_source,
      snat_out_iface: .snat_out_iface,
      snat_target: .snat_target,
      snat_count: .snat_count
    }' \
  | if [[ -n "$FILTER" ]]; then devkit_transform.jsons.key_field_greper.to.jsons.sh "snat_source" "$FILTER" ; else cat ; fi \
  | _emit
done <<< "$INPUT"
