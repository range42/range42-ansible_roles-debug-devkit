#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# PR-NN
# proxmox_snapshot_vm.vm_id.create_snapshot_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh
#
# Reads JSON lines from stdin with at least .vm_id (plain text vm_id also accepted).
# Optional fields : .vm_snapshot_name, .vm_snapshot_description.
# When .vm_snapshot_name is missing, defaults to "<vm_name>-<YYYYMMDD-HHMMSS>" (40 char Proxmox cap).
# When .vm_snapshot_description is missing, mirrors the slow-path default ("<vm_name>-<YYYYMMDD-HHMMSS>").
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="snapshot_vm_create"
SOURCE_TAG="proxmox-api"
DEFAULT_OUTPUT_JSON=true
POLL_TIMEOUT_SECONDS=60

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text - auto-generated snap name)"
  echo
  echo "    echo \"100\" | $(basename "$0")"
  echo
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo
  echo "    echo '{\"vm_id\":100, \"vm_snapshot_name\":\"my-snap\"}' | $(basename "$0")"
  echo "    echo '{\"vm_id\":100, \"vm_snapshot_name\":\"my-snap\", \"vm_snapshot_description\":\"before X\"}' | $(basename "$0")"
  echo "    proxmox_vm.list_with_api.to.jsons.sh | $(basename "$0")"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - create a VM snapshot - direct Proxmox HTTPS API call ($ACTION)"
  echo
  echo OPTIONS
  echo
  echo "                                $(basename "$0") [-h|--help]"
  echo "  STDIN :: [VM_ID|JSON_LINE] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [VM_ID|JSON_LINE] | $(basename "$0") [--text]    - force output as text"
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
  echo "ERROR: no input on stdin. Pipe vm_id(s) (plain text or JSON lines)." >&2
  show_example >&2
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ -z "${RANGE42_ANSIBLE_ROLES__DEVKITS_DIR:-}" ]]; then
  echo "ERROR: RANGE42_ANSIBLE_ROLES__DEVKITS_DIR is not set. Activate a workspace first (range42-context use ...)." >&2
  exit 1
fi
if [[ -z "${RANGE42_VAULT_PASSWORD_FILE:-}" ]]; then
  echo "ERROR: RANGE42_VAULT_PASSWORD_FILE is not set. Activate a workspace first (range42-context use ...)." >&2
  exit 1
fi

VAULT_FILE="$RANGE42_ANSIBLE_ROLES__DEVKITS_DIR/secrets/default_vault.yml"
VAULT_PW="$RANGE42_VAULT_PASSWORD_FILE"

[[ -r "$VAULT_FILE" ]] || { echo "ERROR: vault file not readable: $VAULT_FILE" >&2 ; exit 1 ; }
[[ -r "$VAULT_PW"   ]] || { echo "ERROR: vault password file not readable: $VAULT_PW" >&2 ; exit 1 ; }

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

VAULT_YAML="$(ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PW")"

API_HOST="$(printf '%s\n'         "$VAULT_YAML" | yq -r '.proxmox_api_host')"
API_USER="$(printf '%s\n'         "$VAULT_YAML" | yq -r '.proxmox_api_user')"
API_TOKEN_ID="$(printf '%s\n'     "$VAULT_YAML" | yq -r '.proxmox_api_token_id')"
API_TOKEN_SECRET="$(printf '%s\n' "$VAULT_YAML" | yq -r '.proxmox_api_token_secret')"
NODE="$(printf '%s\n'             "$VAULT_YAML" | yq -r '.proxmox_node')"

for v in API_HOST API_USER API_TOKEN_ID API_TOKEN_SECRET NODE ; do
  if [[ -z "${!v}" || "${!v}" == "null" ]]; then
    echo "ERROR: missing vault key for $v" >&2
    exit 1
  fi
done

AUTH_HEADER="Authorization: PVEAPIToken=${API_USER}!${API_TOKEN_ID}=${API_TOKEN_SECRET}"
BASE_URL="https://${API_HOST}/api2/json/nodes/${NODE}"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

while IFS= read -r LINE ; do
  [[ -z "$LINE" ]] && continue

  # extract fields : vm_id (required), vm_snapshot_name (optional), vm_snapshot_description (optional)
  PARSED="$(printf '%s' "$LINE" | jq -cR '
    (fromjson? // null) as $p |
    if   $p == null                                              then {vm_id: .}
    elif ($p | type) == "object" and ($p | has("vm_id"))         then {
      vm_id:                   ($p.vm_id | tostring),
      vm_snapshot_name:        ($p.vm_snapshot_name        // ""),
      vm_snapshot_description: ($p.vm_snapshot_description // "")
    }
    else                                                              {vm_id: .}
    end
  ' 2>/dev/null || echo '{"vm_id":""}')"

  VM_ID="$(printf '%s' "$PARSED" | jq -r '.vm_id // ""')"
  SNAP_NAME_IN="$(printf '%s' "$PARSED" | jq -r '.vm_snapshot_name // ""')"
  SNAP_DESC_IN="$(printf '%s' "$PARSED" | jq -r '.vm_snapshot_description // ""')"

  if ! [[ "$VM_ID" =~ ^[0-9]+$ ]]; then
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "skip line, cannot extract integer vm_id: $LINE"
    continue
  fi

  # look up vm_name via /status/current (needed for default snap name + description)
  CURRENT_RESP="$(curl -sk -H "$AUTH_HEADER" "${BASE_URL}/qemu/${VM_ID}/status/current" || true)"
  VM_NAME="$(printf '%s' "$CURRENT_RESP" | jq -r '.data.name // "?"')"

  if [[ -z "$SNAP_NAME_IN" ]]; then
    SNAP_NAME="$(printf '%s-%s' "$VM_NAME" "$(date +'%y%m%d-%H%M%S')" | cut -c1-40)"
  else
    SNAP_NAME="$SNAP_NAME_IN"
  fi

  if [[ -z "$SNAP_DESC_IN" ]]; then
    SNAP_DESC="${VM_NAME}-$(date +'%y%m%d-%H%M%S')"
  else
    SNAP_DESC="$SNAP_DESC_IN"
  fi

  POST_RESP="$(curl -sk -X POST -H "$AUTH_HEADER" \
    --data-urlencode "snapname=${SNAP_NAME}" \
    --data-urlencode "description=${SNAP_DESC}" \
    "${BASE_URL}/qemu/${VM_ID}/snapshot" || true)"
  UPID="$(printf '%s' "$POST_RESP" | jq -r '.data // empty')"
  if [[ -z "$UPID" || "$UPID" == "null" ]]; then
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "POST snapshot did not return a UPID for vm_id ${VM_ID} snap '${SNAP_NAME}'. response: $POST_RESP"
    continue
  fi

  UPID_ENC="$(jq -rn --arg u "$UPID" '$u|@uri')"
  elapsed=0
  TASK_STATUS=""
  while (( elapsed < POLL_TIMEOUT_SECONDS )); do
    TASK_RESP="$(curl -sk -H "$AUTH_HEADER" "${BASE_URL}/tasks/${UPID_ENC}/status" || true)"
    TASK_STATUS="$(printf '%s' "$TASK_RESP" | jq -r '.data.status // empty')"
    if [[ "$TASK_STATUS" == "stopped" ]]; then
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if [[ "${TASK_STATUS:-}" != "stopped" ]]; then
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "snapshot create task ${UPID} did not complete within ${POLL_TIMEOUT_SECONDS}s ; emitting result anyway."
  fi

  OUT_JSON="$(jq -nc \
    --arg action "$ACTION" \
    --arg source "$SOURCE_TAG" \
    --arg proxmox_node "$NODE" \
    --arg vm_id "$VM_ID" \
    --arg vm_name "$VM_NAME" \
    --arg vm_snapshot_name "$SNAP_NAME" \
    --arg vm_snapshot_description "$SNAP_DESC" \
    '{
      action:$action,
      source:$source,
      proxmox_node:$proxmox_node,
      vm_id:$vm_id,
      vm_name:$vm_name,
      vm_snapshot_name:$vm_snapshot_name,
      vm_snapshot_description:$vm_snapshot_description
    }')"

  if [[ "$OUTPUT_JSON" == true ]]; then
    printf '%s\n' "$OUT_JSON"
  else
    printf '%s\n' "$OUT_JSON" | jq -r 'to_entries[] | "\(.key)=\(.value)"'
  fi
done
