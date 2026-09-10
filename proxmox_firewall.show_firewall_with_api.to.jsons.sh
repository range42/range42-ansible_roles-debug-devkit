#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_firewall.show_firewall_with_api.to.jsons.sh
#
# Direct Proxmox HTTPS API twin of proxmox_firewall.show_firewall.to.jsons.sh : the same
# request, the same lines, only 'source' says 'proxmox-api'. Three GET for the host and the
# guest list, then two GET per guest of the scope (firewall options, config), so a scenario
# of four guests reads in about a second where the ansible path needs twenty to thirty.
#
# The engine delegates here as soon as the api answers ; RANGE42_PROXMOX_API_FORCE=off keeps
# the ansible path. Called directly, this twin honours the same options as the engine.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="show_firewall"
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
  local STDIN_JSON_DATA=(
    '{"vm_id":2001}'
    '{"vm_id":2002}'
  )
  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"' --json/'
  echo
  echo "    printf '2001\\n2002\\n' | $(basename "$0") --table"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the show_firewall view, calls the Proxmox HTTPS API directly "
  echo
  echo OPTIONS
  echo
  echo "                  $(basename "$0") [-h|--help]"
  echo "  [STDIN :: ids] | $(basename "$0") [--scope vm_id|vm_ids|scenario|node|dc|all] [--json|--text|--table] [vm_id]"
  echo
  echo "  see proxmox_firewall.show_firewall.to.jsons.sh --help for the scopes and the lines ; same contract here"
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

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# one GET : the body in a file, the http code in HTTP_CODE, the body in BODY
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

_get() {
  local url="$1"
  HTTP_CODE="$(curl -sk --max-time 10 -o "$TMP_DIR/body" -w '%{http_code}' -H "$AUTH_HEADER" "$url" 2>/dev/null || echo "000")"
  BODY="$(cat "$TMP_DIR/body" 2>/dev/null || true)"
  : > "$TMP_DIR/body"
}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the host : datacenter options, node options, the guests the node runs. Without them there
# is nothing to report on, so these three are the only reads that end the run.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

_get "${BASE_URL}/cluster/firewall/options"
[[ "$HTTP_CODE" == "200" ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot read the datacenter firewall options (http ${HTTP_CODE}) : nothing to report on" ; exit 1 ; }
DC_ENABLE=$(printf '%s' "$BODY" | jq -c '.data.enable // null')

_get "${BASE_URL}/nodes/${NODE}/firewall/options"
[[ "$HTTP_CODE" == "200" ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot read the firewall options of node ${NODE} (http ${HTTP_CODE}) : nothing to report on" ; exit 1 ; }
ND_ENABLE=$(printf '%s' "$BODY" | jq -c '.data.enable // null')

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
# the lines. A switch is 0, 1 or null (never set) on both paths ; the card flag likewise.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JQ_DEFS='def sw: if . == null then null else (tostring | tonumber) end;
         def on: (. != null) and ((. | tostring) != "0") and ((. | tostring) != "");'

emit() { printf '%s\n' "$1" >> "$TMP_DIR/lines" ; }
: > "$TMP_DIR/lines"

emit "$(jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson dc "$DC_ENABLE" --argjson nd "$ND_ENABLE" \
  "$JQ_DEFS"'
    {
      level: "host",
      action: $action,
      source: $src,
      proxmox_node: $node,
      datacenter_enable: ($dc | sw),
      node_enable: ($nd | sw)
    }')"

while IFS= read -r ID; do
  [[ -n "$ID" ]] || continue
  ENTRY=$(printf '%s' "$GUESTS" | jq -c --argjson id "$ID" 'first(.[] | select(.vm_id == $id)) // empty')
  if [[ -z "$ENTRY" ]]; then
    emit "$(jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson id "$ID" \
      '
      {
        level: "absent",
        action: $action,
        source: $src,
        proxmox_node: $node,
        vm_id: $id
      }')"
    continue
  fi

  _get "${BASE_URL}/nodes/${NODE}/qemu/${ID}/firewall/options"
  if [[ "$HTTP_CODE" != "200" ]]; then
    emit "$(jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson id "$ID" --arg reason "http ${HTTP_CODE} on firewall/options" \
      '
      {
        level: "error",
        action: $action,
        source: $src,
        proxmox_node: $node,
        vm_id: $id,
        reason: $reason
      }')"
    continue
  fi
  G_ENABLE=$(printf '%s' "$BODY" | jq -c '.data.enable // null')

  _get "${BASE_URL}/nodes/${NODE}/qemu/${ID}/config"
  if [[ "$HTTP_CODE" != "200" ]]; then
    emit "$(jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson id "$ID" --arg reason "http ${HTTP_CODE} on config" \
      '
      {
        level: "error",
        action: $action,
        source: $src,
        proxmox_node: $node,
        vm_id: $id,
        reason: $reason
      }')"
    continue
  fi

  # the cards : netN = "type=MAC,bridge=X,firewall=1,..." parsed like the role does
  CARDS=$(printf '%s' "$BODY" | jq -c '
    .data
    | to_entries
    | map(select(.key | test("^net[0-9]+$")))
    | sort_by(.key | ltrimstr("net") | tonumber)
    | .[]
    | (.value | split(",")) as $parts
    | ( $parts[1:]
        | map(select(test("=")) | split("=") | {(.[0]): (.[1:] | join("="))})
        | add // {}
      ) as $opts
    | {
        device: .key,
        bridge: ($opts.bridge // null),
        firewall: ($opts.firewall // null)
      }')

  if [[ -z "$CARDS" ]]; then
    emit "$(jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson entry "$ENTRY" --argjson dc "$DC_ENABLE" --argjson nd "$ND_ENABLE" --argjson g "$G_ENABLE" \
      "$JQ_DEFS"'
      {
        level: "guest",
        action: $action,
        source: $src,
        proxmox_node: $node,
        vm_id: $entry.vm_id,
        vm_name: $entry.vm_name,
        vm_status: $entry.vm_status,
        vm_template: $entry.vm_template,
        datacenter_enable: ($dc | sw),
        node_enable: ($nd | sw),
        guest_enable: ($g | sw),
        cards: 0,
        effectively_filtered: false,
        missing: ["no network card"]
      }')"
    continue
  fi

  printf '%s\n' "$CARDS" | jq -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" --argjson entry "$ENTRY" --argjson dc "$DC_ENABLE" --argjson nd "$ND_ENABLE" --argjson g "$G_ENABLE" \
    "$JQ_DEFS"'
    ($dc | sw)       as $d
    | ($nd | sw)      as $n
    | ($g | sw)       as $ge
    | (.firewall | sw) as $f
    | {
        level: "card",
        action: $action,
        source: $src,
        proxmox_node: $node,
        vm_id: $entry.vm_id,
        vm_name: $entry.vm_name,
        vm_status: $entry.vm_status,
        vm_template: $entry.vm_template,
        vm_network_device: .device,
        vm_network_bridge: .bridge,
        datacenter_enable: $d,
        node_enable: $n,
        guest_enable: $ge,
        card_firewall_flag: $f,
        node_enable_is_informational: true,
        effectively_filtered: (($d | on) and ($ge | on) and ($f | on)),
        missing: ((if ($d  | on) then [] else ["datacenter_enable"]  end)
                + (if ($ge | on) then [] else ["guest_enable"]       end)
                + (if ($f  | on) then [] else ["card_firewall_flag"] end))
      }' >> "$TMP_DIR/lines"
done < <(printf '%s' "$IDS" | jq -r '.[]')

proxmox__inc.show_firewall.render.sh "$OUTPUT" < "$TMP_DIR/lines"
