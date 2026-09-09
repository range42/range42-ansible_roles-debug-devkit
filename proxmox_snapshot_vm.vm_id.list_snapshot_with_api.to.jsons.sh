#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# PR-NN
# proxmox_snapshot_vm.vm_id.list_snapshot_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_snapshot_vm.vm_id.list_snapshot.to.jsons.sh
# Reads vm_id(s) from stdin, GETs /api2/json/nodes/<node>/qemu/<vmid>/snapshot ,
# emits one canonical JSON line per snapshot (across all vm_ids on stdin).
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="snapshot_vm_list"
SOURCE_TAG="proxmox-api"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text)"
  echo
  echo "    echo \"100\" | $(basename "$0")"
  echo "    echo \"101\" | $(basename "$0") --json"
  echo
  echo "  :: WITH VALUES FROM STDIN (as JSON lines)"
  echo
  echo "    proxmox_vm.list.to.jsons.sh          | $(basename "$0")"
  echo "    proxmox_vm.list_with_api.to.jsons.sh | $(basename "$0")"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - list VM snapshots - direct Proxmox HTTPS API call ($ACTION)"
  echo
  echo OPTIONS
  echo
  echo "                     $(basename "$0") [-h|--help]"
  echo "  STDIN :: [VM_ID] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [VM_ID] | $(basename "$0") [--text]    - force output as text"
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

# shared context guard : same refusals as the ansible path
proxmox__inc.warmup_checks.sh

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

  VM_ID="$(printf '%s' "$LINE" | jq -rR '
    (fromjson? // null) as $p |
    if   $p == null                                              then .
    elif ($p | type) == "object" and ($p | has("vm_id"))         then ($p.vm_id | tostring)
    else . end
  ' 2>/dev/null || true)"

  if ! [[ "$VM_ID" =~ ^[0-9]+$ ]]; then
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "skip line, cannot extract integer vm_id: $LINE"
    continue
  fi

  RESPONSE="$(curl -sk -H "$AUTH_HEADER" "${BASE_URL}/qemu/${VM_ID}/snapshot" || true)"

  if ! printf '%s' "$RESPONSE" | jq -e '.data' >/dev/null 2>&1; then
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "GET snapshot list failed for vm_id ${VM_ID}. response: $RESPONSE"
    continue
  fi

  RESHAPED="$(printf '%s' "$RESPONSE" | jq -c \
    --arg action "$ACTION" \
    --arg src    "$SOURCE_TAG" \
    --arg node   "$NODE" \
    --arg vm_id  "$VM_ID" \
    '
      .data[] | {
        action:                   $action,
        source:                   $src,
        proxmox_node:             $node,
        vm_id:                    $vm_id,
        vm_snapshot_name:         (.name        // "?"),
        vm_snapshot_description:  (.description // ""),
        vm_snapshot_time:         (.snaptime    // 0),
        vm_snapshot_parent:       (.parent      // "")
      }
    ')"

  if [[ "$OUTPUT_JSON" == true ]]; then
    printf '%s\n' "$RESHAPED"
  else
    printf '%s\n' "$RESHAPED" | jq -r '"[\(.action)] vm_id=\(.vm_id)  snap=\(.vm_snapshot_name)  time=\(.vm_snapshot_time)  parent=\(.vm_snapshot_parent)  desc=\(.vm_snapshot_description)"'
  fi
done
