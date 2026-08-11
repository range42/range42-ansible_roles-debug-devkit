#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# PR-NN
# proxmox_vm.list_with_api.to.jsons.sh
# Direct Proxmox HTTPS API variant of proxmox_vm.list.to.jsons.sh.
# Bypasses the ansible-playbook wrapper and talks to /api2/json/ via curl.
# Output JSON shape mirrors the Ansible role byte-for-byte except
# 'source' is set to 'proxmox-api' (instead of 'proxmox').
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="vm_list"
SOURCE_TAG="proxmox-api"
DEFAULT_OUTPUT_JSON=true
ARG_VM_NAME_FILTER=""

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: BASIC USAGE"
  echo
  echo "    $(basename "$0")"
  echo "    $(basename "$0") --json"
  echo "    $(basename "$0") --text"
  echo
  echo "  :: WITH A vm_name SUBSTRING FILTER (case-insensitive)"
  echo
  echo "    $(basename "$0") vm_test_01"
  echo "    $(basename "$0") group_01 --json"
  echo
  echo "  :: PIPE INTO OTHER DEVKIT SCRIPTS"
  echo
  echo "    $(basename "$0") | jq -r '.vm_id'"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo
  echo NAME
  echo "  $(basename "$0") - list VMs - calls Proxmox HTTPS API directly"
  echo
  echo OPTION
  echo "  $(basename "$0") [-h|--help]"
  echo "  $(basename "$0") [--json]                               - force JSON output (default)"
  echo "  $(basename "$0") [partial_or_complete_vm_name] [--json] - filter on vm_name (case-insensitive)"
  echo "  $(basename "$0") [--text]                               - human-readable output (debug)"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# argument parsing : --json | --text | optional positional vm_name filter
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_JSON=true; shift ;;
    --text) OUTPUT_JSON=false; shift ;;
    -*)
      echo "ERROR: unknown flag: $1" >&2
      show_example >&2
      exit 1
      ;;
    *)
      if [[ -z "$ARG_VM_NAME_FILTER" ]]; then
        ARG_VM_NAME_FILTER="$1"
        shift
      else
        echo "ERROR: wrong number of arguments." >&2
        show_example >&2
        exit 1
      fi
      ;;
  esac
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# sanity checks on the workspace environment
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

if [[ ! -f "$VAULT_FILE" ]]; then
  echo "ERROR: vault file not found: $VAULT_FILE" >&2
  exit 1
fi

if [[ ! -f "$VAULT_PW" ]]; then
  echo "ERROR: vault password file not found: $VAULT_PW" >&2
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# decrypt the vault once, then yq the fields we need
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

VAULT_YAML=$(ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PW")

API_HOST=$(printf '%s\n' "$VAULT_YAML" | yq -r '.proxmox_api_host')
API_USER=$(printf '%s\n' "$VAULT_YAML" | yq -r '.proxmox_api_user')
API_TOKEN_ID=$(printf '%s\n' "$VAULT_YAML" | yq -r '.proxmox_api_token_id')
API_TOKEN_SECRET=$(printf '%s\n' "$VAULT_YAML" | yq -r '.proxmox_api_token_secret')
NODE=$(printf '%s\n' "$VAULT_YAML" | yq -r '.proxmox_node')

for v in API_HOST API_USER API_TOKEN_ID API_TOKEN_SECRET NODE; do
  if [[ -z "${!v}" || "${!v}" == "null" ]]; then
    echo "ERROR: vault key for $v is empty or missing." >&2
    exit 1
  fi
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# call the Proxmox API : GET /api2/json/nodes/{node}/qemu
# validate_certs: no in the role => curl -sk here (skip TLS verification)
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

AUTH_HEADER="Authorization: PVEAPIToken=${API_USER}!${API_TOKEN_ID}=${API_TOKEN_SECRET}"
URL="https://${API_HOST}/api2/json/nodes/${NODE}/qemu"

RESPONSE=$(curl -sk -H "$AUTH_HEADER" "$URL") || {
  echo "ERROR: curl call failed for $URL" >&2
  exit 1
}

if ! printf '%s' "$RESPONSE" | jq -e '.data' >/dev/null 2>&1; then
  echo "ERROR: Proxmox API did not return a .data field. Raw response:" >&2
  printf '%s\n' "$RESPONSE" >&2
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# reshape with jq to match the canonical vm_list per-VM JSON shape
# (same keys as vm_list.yaml set_fact, with source set to "proxmox-api")
# vm_meta is then stripped to match the existing script's final stdout.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

RESHAPED=$(printf '%s' "$RESPONSE" | jq --arg node "$NODE" --arg src "$SOURCE_TAG" '
  .data[] | {
    action:       "vm_list",
    source:       $src,
    proxmox_node: $node,
    vm_name:      (.name     // "?"),
    vm_status:    (.status   // "?"),
    vm_id:        (.vmid     // "?"),
    vm_uptime:    (.uptime   // "?"),
    vm_template:  (.template // 0),
    vm_tags:      (.tags     // ""),
    vm_meta: {
      cpu_current_usage:  (.cpu       // "?"),
      cpu_allocated:      (.cpus      // "?"),
      disk_current_usage: (.disk      // "?"),
      disk_read:          (.diskread  // "?"),
      disk_write:         (.diskwrite // "?"),
      disk_max:           (.maxdisk   // "?"),
      ram_current_usage:  (.mem       // "?"),
      ram_max:            (.maxmem    // "?"),
      net_in:             (.netin     // "?"),
      net_out:            (.netout    // "?")
    }
  } | del(.vm_meta)
')

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# optional case-insensitive substring filter on vm_name (JSON mode only)
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ "$OUTPUT_JSON" == true ]]; then

  if [[ -n "$ARG_VM_NAME_FILTER" ]]; then
    printf '%s\n' "$RESHAPED" | jq -c --arg needle "$ARG_VM_NAME_FILTER" '
      select((.vm_name | ascii_downcase) | contains($needle | ascii_downcase))
    '
  else
    printf '%s\n' "$RESHAPED" | jq -c '.'
  fi

else

  # text output : simple human readable projection (debug)
  printf '%s\n' "$RESHAPED" | jq -r '
    "[\(.action)] \(.vm_id)\t\(.vm_status)\t\(.vm_name)\t(node=\(.proxmox_node), source=\(.source))"
  '

fi

exit 0
