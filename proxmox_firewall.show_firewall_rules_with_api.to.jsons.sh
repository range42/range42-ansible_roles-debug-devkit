#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_firewall.show_firewall_rules_with_api.to.jsons.sh
#
# Direct Proxmox HTTPS API twin of proxmox_firewall.show_firewall_rules.to.jsons.sh : the same
# request, the same lines, only 'source' says 'proxmox-api'. Three GET for the two host levels and
# the guest list, then one GET per guest of the scope.
#
# The engine delegates here as soon as the api answers ; RANGE42_PROXMOX_API_FORCE=off keeps the
# ansible path. Called directly, this twin honours the same options as the engine.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="show_firewall_rules"
SOURCE_TAG="proxmox-api"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: THE ACTIVE SCENARIO (no stdin), THE WHOLE NODE, ONE GUEST"
  echo
  echo "    $(basename "$0") --table"
  echo "    $(basename "$0") --scope node --table"
  echo "    $(basename "$0") 2001"
  echo
  echo "  :: A SET OF GUESTS ON STDIN (plain ids or json lines)"
  echo
  echo "    printf '2001\\n2002\\n' | $(basename "$0") --table"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the firewall rules of the datacenter, the node and the guests, through the api "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help]"
  echo "  [STDIN :: ids] | $(basename "$0") [--scope vm_id|vm_ids|scenario|node|dc|all] [--json|--text|--table] [vm_id]"
  echo
  echo "  see proxmox_firewall.show_firewall_rules.to.jsons.sh --help for the scopes and the lines ; same contract here"
  echo "  --request <json>   internal, set by the engine when it delegates : the request already parsed"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the context guard first : this twin reads the vault through the same link as the engine
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh

if [[ "${1:-}" == "--request" ]]; then
  REQ="${2:-}"
  [[ -n "$REQ" ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh " --request needs the json of a parsed request" ; exit 1 ; }
else
  REQ=$(proxmox__inc.show_firewall.request.sh "$@")
fi

OUTPUT=$(printf '%s' "$REQ" | jq -r '.output')

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the api credentials and the node come from the vault of the active workspace
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

VAULT_FILE="${RANGE42_ANSIBLE_ROLES__DEVKITS_DIR%/}/secrets/default_vault.yml"
VAULT_PW="$RANGE42_VAULT_PASSWORD_FILE"
[[ -r "$VAULT_FILE" ]] || { echo "ERROR: vault file not readable: $VAULT_FILE" >&2 ; exit 1 ; }

VAULT_YAML="$(ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PW")"
API_HOST="$(printf '%s\n'         "$VAULT_YAML" | yq -r '.proxmox_api_host')"
API_USER="$(printf '%s\n'         "$VAULT_YAML" | yq -r '.proxmox_api_user')"
API_TOKEN_ID="$(printf '%s\n'     "$VAULT_YAML" | yq -r '.proxmox_api_token_id')"
API_TOKEN_SECRET="$(printf '%s\n' "$VAULT_YAML" | yq -r '.proxmox_api_token_secret')"
NODE="$(printf '%s\n'             "$VAULT_YAML" | yq -r '.proxmox_node')"
for v in API_HOST API_USER API_TOKEN_ID API_TOKEN_SECRET NODE; do
  if [[ -z "${!v}" || "${!v}" == "null" ]]; then
    echo "ERROR: missing vault key for $v" >&2
    exit 1
  fi
done

AUTH_HEADER="Authorization: PVEAPIToken=${API_USER}!${API_TOKEN_ID}=${API_TOKEN_SECRET}"
BASE_URL="https://${API_HOST}/api2/json"

# a proxmox_node given on stdin is ignored : the node comes from the vault (one node per workspace)
while IFS= read -r other; do
  [[ -z "$other" || "$other" == "$NODE" ]] || devkit_utils.text.echo_trace.to.text.to.stderr.sh "proxmox_node ${other} given on stdin is ignored, the node comes from the vault : ${NODE}"
done < <(printf '%s' "$REQ" | jq -r '.stdin_nodes[]?')

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

_get() {
  local url="$1"
  HTTP_CODE="$(curl -sk --max-time 10 -o "$TMP_DIR/body" -w '%{http_code}' -H "$AUTH_HEADER" "$url" 2>/dev/null || echo "000")"
  BODY="$(cat "$TMP_DIR/body" 2>/dev/null || true)"
  : > "$TMP_DIR/body"
}


# usage: _emit_rules <level> <prefix> <extra json>   the twelve fields the reading actions publish,
# prefixed per level, an absent one omitted as the ansible path omits it
_emit_rules() {
  printf '%s' "$BODY" | jq -c --arg level "$1" --arg p "$2" --argjson extra "$3" '
    .data[]? as $r
    | ( {
          pos:     $r.pos,
          action:  $r.action,
          type:    $r.type,
          iface:   $r.iface,
          source:  $r.source,
          dest:    $r.dest,
          proto:   $r.proto,
          dport:   $r.dport,
          sport:   $r.sport,
          enable:  $r.enable,
          comment: $r.comment,
          log:     $r.log
        }
        | with_entries(select(.value != null))
        | with_entries(.key |= $p + .)
      ) as $fields
    | { level: $level }
    + $extra
    + $fields'
}

: > "$TMP_DIR/lines"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the two host levels : they apply whatever the scope, so they always come first. Without them
# there is nothing to report on, so these reads are the ones that end the run.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

EXTRA_HOST=$(jq -n -c --arg a "$ACTION" --arg s "$SOURCE_TAG" --arg n "$NODE" '
  {
    action: $a,
    source: $s,
    proxmox_node: $n
  }')

_get "${BASE_URL}/cluster/firewall/rules"
[[ "$HTTP_CODE" == "200" ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot read the datacenter firewall rules (http ${HTTP_CODE}) : nothing to report on" ; exit 1 ; }
_emit_rules dc_rule "dc_fw_" "$EXTRA_HOST" >> "$TMP_DIR/lines"

_get "${BASE_URL}/nodes/${NODE}/firewall/rules"
[[ "$HTTP_CODE" == "200" ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot read the firewall rules of node ${NODE} (http ${HTTP_CODE}) : nothing to report on" ; exit 1 ; }
_emit_rules node_rule "node_fw_" "$EXTRA_HOST" >> "$TMP_DIR/lines"

_get "${BASE_URL}/nodes/${NODE}/qemu"
[[ "$HTTP_CODE" == "200" ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot list the guests of node ${NODE} (http ${HTTP_CODE}) : nothing to report on" ; exit 1 ; }
GUESTS=$(printf '%s' "$BODY" | jq -c '
  [ .data[]
    | {
        vm_id: .vmid,
        vm_name: (.name // "?"),
        vm_status: (.status // "?"),
        vm_template: (.template // 0)
      }
  ]
  | sort_by(.vm_id)')

IDS=$(printf '%s' "$REQ" | jq -c --argjson guests "$GUESTS" 'if .ids == null then ($guests | map(.vm_id)) else .ids end')

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the guests of the scope, in the order asked
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

while IFS= read -r ID; do
  [[ -n "$ID" ]] || continue
  ENTRY=$(printf '%s' "$GUESTS" | jq -c --argjson id "$ID" 'first(.[] | select(.vm_id == $id)) // empty')
  if [[ -z "$ENTRY" ]]; then
    jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson id "$ID" \
      '
      {
        level: "absent",
        action: $action,
        source: $src,
        proxmox_node: $node,
        vm_id: $id
      }' >> "$TMP_DIR/lines"
    continue
  fi

  _get "${BASE_URL}/nodes/${NODE}/qemu/${ID}/firewall/rules"
  if [[ "$HTTP_CODE" != "200" ]]; then
    jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson id "$ID" --arg reason "http ${HTTP_CODE} on firewall/rules" \
      '
      {
        level: "error",
        action: $action,
        source: $src,
        proxmox_node: $node,
        vm_id: $id,
        reason: $reason
      }' >> "$TMP_DIR/lines"
    continue
  fi

  EXTRA_GUEST=$(jq -n -c --arg a "$ACTION" --arg s "$SOURCE_TAG" --arg n "$NODE" --argjson e "$ENTRY" \
    '
    {
      action: $a,
      source: $s,
      proxmox_node: $n,
      vm_id: $e.vm_id,
      vm_name: $e.vm_name,
      vm_status: $e.vm_status,
      vm_template: $e.vm_template
    }')
  BEFORE=$(wc -l < "$TMP_DIR/lines")
  _emit_rules guest_rule "vm_fw_" "$EXTRA_GUEST" >> "$TMP_DIR/lines"
  if [[ "$(wc -l < "$TMP_DIR/lines")" -eq "$BEFORE" ]]; then
    printf '%s' "$EXTRA_GUEST" | jq -c '
      { level: "guest" }
      + .
      + { rules: 0 }' >> "$TMP_DIR/lines"
  fi
done < <(printf '%s' "$IDS" | jq -r '.[]')

# the guest table is titled with the perimeter that was ASKED : at scope node a guest with an empty
# chain only shows in the line below the table, so the rows alone say nothing about the perimeter
GUESTS_LABEL=$(printf '%s' "$REQ" | jq -r --arg node "$NODE" '
  if .scope == "scenario" then
    "scenario: " + (.scenario_name // "?")
  elif .scope == "vm_id" then
    (.ids[0] | tostring)
  elif .scope == "vm_ids" then
    ((.ids | length | tostring) + " ids on stdin")
  elif .scope == "node" then
    ("node " + $node + " : every guest")
  else
    "datacenter : every guest"
  end')

proxmox__inc.show_firewall_rules.render.sh "$OUTPUT" "$GUESTS_LABEL" < "$TMP_DIR/lines"
