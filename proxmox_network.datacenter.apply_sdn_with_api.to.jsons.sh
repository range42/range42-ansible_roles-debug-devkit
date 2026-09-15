#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox_network.datacenter.apply_sdn_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_network.datacenter.apply_sdn.to.jsons.sh
#
# PUT /cluster/sdn, then poll the task it started until it stops, and refuse anything
# other than exitstatus OK : the same contract as the role action network_apply_sdn.
#
# The node that runs the task is read back FROM THE UPID (its second field), never assumed
# to be the node of the vault : on a multi node cluster the task may run elsewhere.
#
# >>> THE APPLY IS NOT IDEMPOTENT <<<
# Every apply adds one SNAT rule per subnet that has snat=1. Always follow it with the
# delete_extra_snat_rules devkit, or call the composites that do it for you.
#
# Optional fields on the json line, as in the role : sdn_apply_poll_retries (60) and
# sdn_apply_poll_delay (2 seconds). Without stdin, one apply on the node of the vault, as
# the ansible path does.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="network_apply_sdn"
SOURCE_TAG="proxmox-api"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITHOUT STDIN : one apply on the node of the vault"
  echo
  echo "    $(basename "$0")"
  echo
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo
  echo "    echo '{\"proxmox_node\":\"px-testing\"}' | $(basename "$0")"
  echo "    echo '{\"sdn_apply_poll_retries\":30,\"sdn_apply_poll_delay\":1}' | $(basename "$0") --text"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - apply the pending SDN configuration and wait for the task - direct Proxmox HTTPS API call ($ACTION)"
  echo
  echo OPTIONS
  echo
  echo "                             $(basename "$0") [-h|--help]"
  echo "  STDIN :: [JSON_LINE] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [JSON_LINE] | $(basename "$0") [--text]    - force output as text"
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

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# shared context guard : same refusals as the ansible path
proxmox__inc.warmup_checks.sh

# the api credentials of the active workspace, and the request helpers
source proxmox__inc.api_auth.sh

_trace() { devkit_utils.text.echo_trace.to.text.to.stderr.sh "$@" ; }
_error() { devkit_utils.text.echo_error.to.text.to.stderr.sh "$@" ; }
_emit()  { if [[ "$OUTPUT_JSON" == true ]]; then jq -c . ; else jq -r 'to_entries[] | "\(.key)=\(.value)"' ; fi ; }

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# without stdin the ansible path applies once on the node of the vault : same here
if [ -t 0 ]; then
  INPUT="$(printf '{"proxmox_node":"%s"}\n' "$NODE")"
else
  INPUT="$(cat -)"
fi

# a here-string, not a pipe : an exit inside the loop must end the script, not a subshell
while IFS= read -r LINE ; do
  [[ -z "$LINE" ]] && continue

  REQ="$(printf '%s' "$LINE" | jq -cR '(fromjson? // .) as $v | if ($v | type) == "object" then $v else {proxmox_node: $v} end' 2>/dev/null || echo '{}')"

  LINE_NODE="$(printf '%s' "$REQ" | jq -r '.proxmox_node // empty')"
  [[ -z "$LINE_NODE" || "$LINE_NODE" == "$NODE" ]] || _trace "proxmox_node ${LINE_NODE} given on stdin is ignored, the node comes from the vault : ${NODE}"

  RETRIES="$(printf '%s' "$REQ" | jq -r '.sdn_apply_poll_retries // 60 | tostring')"
  DELAY="$(printf '%s' "$REQ" | jq -r '.sdn_apply_poll_delay // 2 | tostring')"
  [[ "$RETRIES" =~ ^[0-9]+$ ]] || RETRIES=60
  [[ "$DELAY" =~ ^[0-9]+$ ]] || DELAY=2

  _api_put "${API_URL}/cluster/sdn"
  if [[ "$HTTP_CODE" != "200" ]]; then
    _error "PUT /cluster/sdn failed (http ${HTTP_CODE}) : ${BODY}"
    exit 1
  fi

  UPID="$(printf '%s' "$BODY" | jq -r '.data // empty')"
  if [[ "$UPID" != UPID:* ]]; then
    _error "the apply did not return a usable UPID, so there is no task to wait for and no way to tell whether the configuration was applied. Got: ${UPID:-<nothing>}"
    exit 1
  fi
  TASK_NODE="$(printf '%s' "$UPID" | cut -d: -f2)"
  if [[ -z "$TASK_NODE" ]]; then
    _error "the UPID carries no node in its second field : ${UPID}"
    exit 1
  fi
  _trace "apply task ${UPID} running on node ${TASK_NODE}"

  UPID_ENC="$(jq -rn --arg u "$UPID" '$u | @uri')"
  TASK_STATUS=""
  TASK_EXIT=""
  attempt=0
  while (( attempt < RETRIES )); do
    _api_get "${API_URL}/nodes/${TASK_NODE}/tasks/${UPID_ENC}/status"
    if [[ "$HTTP_CODE" == "200" ]]; then
      TASK_STATUS="$(printf '%s' "$BODY" | jq -r '.data.status // empty')"
      TASK_EXIT="$(printf '%s' "$BODY" | jq -r '.data.exitstatus // empty')"
      [[ "$TASK_STATUS" == "stopped" ]] && break
    fi
    sleep "$DELAY"
    attempt=$((attempt + 1))
  done

  if [[ "$TASK_STATUS" != "stopped" ]]; then
    _error "the SDN apply task ${UPID} did not stop within ${RETRIES} x ${DELAY}s. Read the task log on ${TASK_NODE} before retrying."
    exit 1
  fi
  if [[ "$TASK_EXIT" != "OK" ]]; then
    _error "the SDN apply task ${UPID} ended with exitstatus=${TASK_EXIT:-<none>}. Read the task log on ${TASK_NODE} before retrying."
    exit 1
  fi

  jq -nc \
    --arg action "$ACTION" \
    --arg source "$SOURCE_TAG" \
    --arg node "$NODE" \
    --arg upid "$UPID" \
    --arg task_node "$TASK_NODE" \
    --arg status "$TASK_STATUS" \
    --arg exitstatus "$TASK_EXIT" \
    '{
      action: $action,
      source: $source,
      proxmox_node: $node,
      apply_upid: $upid,
      apply_node: $task_node,
      apply_status: $status,
      apply_exitstatus: $exitstatus
    }' | _emit
done <<< "$INPUT"
