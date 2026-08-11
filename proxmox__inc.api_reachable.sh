#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# PR-NN
#
# Probe the Proxmox HTTPS API for reachability + token validity.
# Exits 0  : API reachable AND auth accepted (HTTP 200 on /nodes/<node>/qemu).
# Exits 1  : any other case (no workspace, vault unreadable, missing field,
#            network unreachable, TLS error, HTTP non-200).
#
# Silent on stdout/stderr ; caller is expected to log via echo_trace.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

PROBE_TIMEOUT_SECONDS=2

[[ -n "${RANGE42_ANSIBLE_ROLES__DEVKITS_DIR:-}" ]] || exit 1
[[ -n "${RANGE42_VAULT_PASSWORD_FILE:-}"        ]] || exit 1

VAULT_FILE="$RANGE42_ANSIBLE_ROLES__DEVKITS_DIR/secrets/default_vault.yml"
VAULT_PW="$RANGE42_VAULT_PASSWORD_FILE"

[[ -r "$VAULT_FILE" ]] || exit 1
[[ -r "$VAULT_PW"   ]] || exit 1

VAULT_YAML="$(ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PW" 2>/dev/null || true)"
[[ -n "$VAULT_YAML" ]] || exit 1

API_HOST="$(printf '%s\n'         "$VAULT_YAML" | yq -r '.proxmox_api_host'         2>/dev/null || true)"
API_USER="$(printf '%s\n'         "$VAULT_YAML" | yq -r '.proxmox_api_user'         2>/dev/null || true)"
API_TOKEN_ID="$(printf '%s\n'     "$VAULT_YAML" | yq -r '.proxmox_api_token_id'     2>/dev/null || true)"
API_TOKEN_SECRET="$(printf '%s\n' "$VAULT_YAML" | yq -r '.proxmox_api_token_secret' 2>/dev/null || true)"
NODE="$(printf '%s\n'             "$VAULT_YAML" | yq -r '.proxmox_node'             2>/dev/null || true)"

for v in API_HOST API_USER API_TOKEN_ID API_TOKEN_SECRET NODE ; do
  if [[ -z "${!v}" || "${!v}" == "null" ]]; then
    exit 1
  fi
done

AUTH_HEADER="Authorization: PVEAPIToken=${API_USER}!${API_TOKEN_ID}=${API_TOKEN_SECRET}"
PROBE_URL="https://${API_HOST}/api2/json/nodes/${NODE}/qemu"

HTTP_CODE="$(curl -sk --max-time "$PROBE_TIMEOUT_SECONDS" -o /dev/null -w '%{http_code}' -H "$AUTH_HEADER" "$PROBE_URL" 2>/dev/null || echo "000")"

if [[ "$HTTP_CODE" == "200" ]]; then
  exit 0
fi
exit 1
