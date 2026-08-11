#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# PR-NN
# proxmox_vm.vm_id.list_vm_and_extract_vm_name_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_vm.vm_id.list_vm_and_extract_vm_name.to.jsons.sh
# Read vm_ids from stdin (plain text or JSON lines), fetch /api2/json/nodes/<node>/qemu
# ONCE, then emit one canonical vm_list JSON line per requested vm_id.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

SOURCE_TAG="proxmox-api"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text)"
  echo
  echo "    echo \"100\" | $(basename "$0")"
  echo "    echo \"101\" | $(basename "$0") --json"
  echo "    echo \"102\" | $(basename "$0") --text"
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
  echo "  $(basename "$0") - list VM status filtered to vm_ids from stdin - direct Proxmox HTTPS API call"
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
# read ALL vm_ids from stdin first ; then we hit the API ONCE for the lookup

VM_IDS=()
while IFS= read -r LINE ; do
  [[ -z "$LINE" ]] && continue
  VID="$(printf '%s' "$LINE" | jq -rR '
    (fromjson? // null) as $p |
    if   $p == null                                              then .
    elif ($p | type) == "object" and ($p | has("vm_id"))         then ($p.vm_id | tostring)
    else . end
  ' 2>/dev/null || true)"

  if [[ "$VID" =~ ^[0-9]+$ ]]; then
    VM_IDS+=("$VID")
  else
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "skip line, cannot extract integer vm_id: $LINE"
  fi
done

if [[ ${#VM_IDS[@]} -eq 0 ]]; then
  echo "ERROR: no valid vm_id found on stdin." >&2
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
URL="https://${API_HOST}/api2/json/nodes/${NODE}/qemu"

RESPONSE="$(curl -sk -H "$AUTH_HEADER" "$URL" || true)"

if ! printf '%s' "$RESPONSE" | jq -e '.data' >/dev/null 2>&1; then
  echo "ERROR: Proxmox API did not return a .data field for $URL." >&2
  echo "Raw response: $RESPONSE" >&2
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# reshape full list once, mirroring proxmox_vm.list_with_api.to.jsons.sh shape

RESHAPED="$(printf '%s' "$RESPONSE" | jq -c --arg node "$NODE" --arg src "$SOURCE_TAG" '
  .data[] | {
    action:       "vm_list",
    source:       $src,
    proxmox_node: $node,
    vm_name:      (.name     // "?"),
    vm_status:    (.status   // "?"),
    vm_id:        (.vmid     // "?"),
    vm_uptime:    (.uptime   // "?"),
    vm_template:  (.template // 0),
    vm_tags:      (.tags     // "")
  }
')"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# emit one matching line per requested vm_id (preserves stdin order, warns on miss)

for VID in "${VM_IDS[@]}"; do
  MATCH="$(printf '%s\n' "$RESHAPED" | jq -c --argjson v "$VID" 'select(.vm_id == $v)')"
  if [[ -z "$MATCH" ]]; then
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "vm_id $VID not found in proxmox node $NODE."
    continue
  fi
  if [[ "$OUTPUT_JSON" == true ]]; then
    printf '%s\n' "$MATCH"
  else
    printf '%s\n' "$MATCH" | jq -r '"[\(.action)] \(.vm_id)\t\(.vm_status)\t\(.vm_name)\t(node=\(.proxmox_node), source=\(.source))"'
  fi
done

exit 0
