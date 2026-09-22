#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox__inc.api_auth.sh
#
# The api credentials of the active workspace, read ONCE from its vault, for the direct
# Proxmox HTTPS API twins (the *_with_api.to.jsons.sh files).
#
# >>> THIS FILE IS SOURCED, NOT EXECUTED <<<
#
#     source proxmox__inc.api_auth.sh
#
# bash resolves a bare name through PATH for `source` exactly as it does for a command
# (shopt sourcepath, on by default), and the variables land in the caller. Every twin used
# to carry these thirty lines as a copy of its own ; a twin now holds only its action.
#
# IT SETS : VAULT_FILE, VAULT_PW, VAULT_YAML, API_HOST, API_USER, API_TOKEN_ID,
#           API_TOKEN_SECRET, NODE, AUTH_HEADER, and API_URL (https://<host>/api2/json).
#
# IT DEFINES three request helpers. Each leaves the http code in HTTP_CODE and the body in
# BODY and never ends the caller by itself : a code of 000 is a transport error, anything
# else is what the api answered. TLS is not verified (curl -k), as the role does with
# validate_certs false. A body is sent as json, as the role does with body_format json.
#
#           _api_get  <url>
#           _api_put  <url> [json body]
#           _api_post <url> <json body>
#
# IT EXITS the caller (rc 1) when no workspace is active, when the vault or its password
# file cannot be read, or when a key is missing : a twin without credentials has nothing
# to say. The context guard is NOT here : every twin runs proxmox__inc.warmup_checks.sh
# before sourcing this, on purpose, so that both paths refuse the same way.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - LIB / INCLUDE to be SOURCED by the *_with_api twins : the api credentials of the active workspace, and three request helpers"
  echo
  echo USAGE
  echo
  echo "  source $(basename "$0")      # inside a twin, right after proxmox__inc.warmup_checks.sh"
  echo
  echo "  sets    : API_HOST API_USER API_TOKEN_ID API_TOKEN_SECRET NODE AUTH_HEADER API_URL"
  echo "  defines : _api_get <url>   _api_put <url> [json]   _api_post <url> <json>   (HTTP_CODE and BODY)"
  echo
  exit 1
fi

if [[ -z "${RANGE42_ANSIBLE_ROLES__DEVKITS_DIR:-}" ]]; then
  echo "ERROR: RANGE42_ANSIBLE_ROLES__DEVKITS_DIR is not set. Activate a workspace first (range42-context use ...)." >&2
  exit 1
fi
if [[ -z "${RANGE42_VAULT_PASSWORD_FILE:-}" ]]; then
  echo "ERROR: RANGE42_VAULT_PASSWORD_FILE is not set. Activate a workspace first (range42-context use ...)." >&2
  exit 1
fi

VAULT_FILE="${RANGE42_ANSIBLE_ROLES__DEVKITS_DIR%/}/secrets/default_vault.yml"
VAULT_PW="$RANGE42_VAULT_PASSWORD_FILE"

[[ -r "$VAULT_FILE" ]] || { echo "ERROR: vault file not readable: $VAULT_FILE" >&2 ; exit 1 ; }
[[ -r "$VAULT_PW"   ]] || { echo "ERROR: vault password file not readable: $VAULT_PW" >&2 ; exit 1 ; }

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
API_URL="https://${API_HOST}/api2/json"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# one request : the http code in HTTP_CODE, the body in BODY. The code travels on the last
# line of the output, after the body, so one call gives both without a temporary file.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

_api_call() {
  local method="$1" url="$2" body="${3:-}" out
  if [[ -n "$body" ]]; then
    out="$(curl -sk --max-time 30 -X "$method" -H "$AUTH_HEADER" -H 'Content-Type: application/json' --data "$body" -w '\n%{http_code}' "$url" 2>/dev/null || true)"
  else
    out="$(curl -sk --max-time 30 -X "$method" -H "$AUTH_HEADER" -w '\n%{http_code}' "$url" 2>/dev/null || true)"
  fi
  if [[ "$out" == *$'\n'* ]]; then
    HTTP_CODE="${out##*$'\n'}"
    BODY="${out%$'\n'*}"
  else
    HTTP_CODE="000"
    BODY=""
  fi
  [[ "$HTTP_CODE" =~ ^[0-9]{3}$ ]] || { HTTP_CODE="000" ; BODY="" ; }
}

_api_get()  { _api_call GET  "$1" ; }
_api_put()  { _api_call PUT  "$1" "${2:-}" ; }
_api_post() { _api_call POST "$1" "$2" ; }
