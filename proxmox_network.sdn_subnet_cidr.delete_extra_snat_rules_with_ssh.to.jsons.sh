#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox_network.sdn_subnet_cidr.delete_extra_snat_rules_with_ssh.to.jsons.sh
# Direct ssh variant of proxmox_network.sdn_subnet_cidr.delete_extra_snat_rules.to.jsons.sh
#
# The role action network_delete_extra_snat_rules is a shell block run on the hypervisor
# through the proxmox_cli group : there is no api for iptables. This twin runs THE SAME
# block on THE SAME host, without one ansible play per network : every json line of stdin
# is a (cidr, wanted count) pair, all the pairs travel in ONE ssh session, and the node
# script runs the block once per pair, in order, stopping at the first refused deletion
# as the role does.
#
# Same guard as the role before anything travels : the cidr must be a well formed
# network with its mask, exactly as iptables renders it (192.168.199.0/24). The wanted
# count defaults to 1. Same output fields as the role, one line per pair ; only `source`
# differs.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="network_delete_extra_snat_rules"
SOURCE_TAG="proxmox-ssh"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text : the cidr, wanted count 1)"
  echo
  echo "    echo \"192.168.199.0/24\" | $(basename "$0")"
  echo
  echo "  :: WITH VALUES FROM STDIN (as JSON lines, one session for all of them)"
  echo
  echo "    printf '%s\\n' '{\"sdn_subnet_cidr\":\"192.168.199.0/24\",\"sdn_snat_want\":0}' '{\"sdn_subnet_cidr\":\"192.168.198.0/24\",\"sdn_snat_want\":1}' | $(basename "$0")"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - delete the extra live SNAT rules of subnets, down to a wanted count - direct ssh run of the role's block ($ACTION)"
  echo
  echo OPTIONS
  echo
  echo "                             $(basename "$0") [-h|--help]"
  echo "  STDIN :: [CIDR|JSON_LINE] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [CIDR|JSON_LINE] | $(basename "$0") [--text]    - force output as text"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_JSON=true ; shift ;;
    --text) OUTPUT_JSON=false ; shift ;;
    *)
      echo "ERROR: unknown arg '$1'" >&2
      show_example >&2
      exit 1
      ;;
  esac
done

if [ -t 0 ]; then
  echo "ERROR: no input on stdin. Pipe cidr(s) (plain text or JSON lines with sdn_subnet_cidr and sdn_snat_want)." >&2
  show_example >&2
  exit 1
fi

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

# every line is checked before anything travels : the same guard as the role, on every pair
CIDRS=()
WANTS=()
while IFS= read -r LINE ; do
  [[ -z "$LINE" ]] && continue
  REQ="$(printf '%s' "$LINE" | jq -cR '(fromjson? // .) as $v | if ($v | type) == "object" then $v else {sdn_subnet_cidr: $v} end' 2>/dev/null || echo '{}')"
  LINE_NODE="$(printf '%s' "$REQ" | jq -r '.proxmox_node // empty')"
  [[ -z "$LINE_NODE" || "$LINE_NODE" == "$NODE" ]] || _trace "proxmox_node ${LINE_NODE} given on stdin is ignored, the node comes from the vault : ${NODE}"
  CIDR="$(printf '%s' "$REQ" | jq -r '.sdn_subnet_cidr // empty | tostring')"
  WANT="$(printf '%s' "$REQ" | jq -r '.sdn_snat_want // 1 | tostring')"
  if ! [[ "$CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    _error "sdn_subnet_cidr must be a CIDR with its mask, exactly as iptables renders it, for instance 192.168.199.0/24. Got: ${CIDR:-<undefined>}. Nothing was changed."
    exit 1
  fi
  if ! [[ "$WANT" =~ ^[0-9]+$ ]]; then
    _error "sdn_snat_want must be a whole number. Got: ${WANT}. Nothing was changed."
    exit 1
  fi
  CIDRS+=("$CIDR")
  WANTS+=("$WANT")
done

if [[ "${#CIDRS[@]}" -eq 0 ]]; then
  _error "no cidr read on stdin, nothing to reconcile."
  exit 1
fi

ARGS=()
for i in "${!CIDRS[@]}" ; do ARGS+=("${CIDRS[$i]}" "${WANTS[$i]}") ; done
_trace "reconciling the live snat rules of ${#CIDRS[@]} network(s) on ${SSH_HOST}, one ssh session"

_node_script_run delete "${ARGS[@]}" || true
RESULT="$NODE_OUT"
RESULT_LINES="$(printf '%s\n' "$RESULT" | grep -c '^{' || true)"

# one line per pair, in order : what came back is projected, then a refusal is reported
i=0
while IFS= read -r ROW ; do
  [[ -z "$ROW" ]] && continue
  [[ "$i" -lt "${#CIDRS[@]}" ]] || break
  printf '%s' "$ROW" | jq -c \
    --arg action "$ACTION" \
    --arg source "$SOURCE_TAG" \
    --arg node "$NODE" \
    --arg host "$SSH_HOST" \
    --arg cidr "${CIDRS[$i]}" \
    '{
      action: $action,
      source: $source,
      proxmox_node: $node,
      subnet_cidr: $cidr,
      snat_host: $host,
      snat_want: .want,
      snat_before: .before,
      snat_after: .after,
      snat_deleted: .deleted
    }' | _emit
  i=$((i + 1))
done <<< "$RESULT"

if [[ "$NODE_RC" -ne 0 ]]; then
  _error "the node script stopped on ${SSH_HOST} after ${RESULT_LINES} of ${#CIDRS[@]} network(s) (rc ${NODE_RC}) : ${NODE_ERR}"
  exit 1
fi
if [[ "$RESULT_LINES" -ne "${#CIDRS[@]}" ]]; then
  _error "the node returned ${RESULT_LINES} line(s) for ${#CIDRS[@]} network(s) : read the live rules with proxmox_network.datacenter.list_snat_rules.to.jsons.sh before trusting any count."
  exit 1
fi
