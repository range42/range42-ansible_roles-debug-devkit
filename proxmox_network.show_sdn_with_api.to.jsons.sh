#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox_network.show_sdn_with_api.to.jsons.sh
#
# Direct Proxmox HTTPS API twin of proxmox_network.show_sdn.to.jsons.sh : the same request, the
# same lines, only 'source' says 'proxmox-api'. One GET for the vnets, then one GET per vnet for
# its subnets - the api serves subnets per vnet only, it has no flat endpoint for them.
#
# THE LIVE SNAT RULES STILL COME THROUGH THE ANSIBLE READER, and this is not an oversight : they
# are not api objects at all. They come from a post-up hook in /etc/network/interfaces.d, so the
# firewall endpoints - which only ever write the PVEFW-* chains - cannot see them. The only way to
# read them is iptables on the node over SSH, which is what
# proxmox_network.datacenter.list_snat_rules.to.jsons.sh does. This twin therefore spares the two
# declaration reads and keeps that one, which is where the view's verdict comes from.
#
# The engine delegates here as soon as the api answers ; RANGE42_PROXMOX_API_FORCE=off keeps the
# ansible path. Called directly, this twin honours the same options as the engine. The join lives
# once, in proxmox__inc.show_sdn.join.sh, so the two paths cannot disagree on a verdict.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ACTION="show_sdn"
SOURCE_TAG="proxmox-api"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: THE ACTIVE SCENARIO (no stdin), THE WHOLE DATACENTER, ONE NETWORK"
  echo
  echo "    $(basename "$0") --table"
  echo "    $(basename "$0") --scope dc --table"
  echo "    $(basename "$0") net143"
  echo
  echo "  :: A SET OF NETWORKS ON STDIN (plain names or json lines)"
  echo
  echo "    printf 'net143\\nnet144\\n' | $(basename "$0") --table"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - the declared SDN of a network beside its live rules, through the api "
  echo
  echo OPTIONS
  echo
  echo "                       $(basename "$0") [-h|--help]"
  echo "  [STDIN :: networks] | $(basename "$0") [--scope sdn_vnet|sdn_vnets|scenario|dc|all] [--json|--text|--table] [vnet]"
  echo
  echo "  see proxmox_network.show_sdn.to.jsons.sh --help for the scopes and the lines ; same contract here"
  echo "  the declaration costs 1 GET plus 1 per vnet ; the live SNAT rules always cost the ansible"
  echo "  reader over SSH, they are not api objects"
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
  REQ=$(proxmox__inc.show_sdn.request.sh "$@")
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

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

_get() {
  local url="$1"
  HTTP_CODE="$(curl -sk --max-time 10 -o "$TMP_DIR/body" -w '%{http_code}' -H "$AUTH_HEADER" "$url" 2>/dev/null || echo "000")"
  BODY="$(cat "$TMP_DIR/body" 2>/dev/null || true)"
  : > "$TMP_DIR/body"
}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the declaration : the vnets, then the subnets of each. Without it there is nothing to report on.
# The keys are the ones the readers publish, an absent one omitted as the ansible path omits it.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

: > "$TMP_DIR/vnets.jsonl"
: > "$TMP_DIR/subnets.jsonl"

_get "${BASE_URL}/cluster/sdn/vnets"
[[ "$HTTP_CODE" == "200" ]] || { devkit_utils.text.echo_error.to.text.to.stderr.sh " cannot read the sdn vnets of the cluster (http ${HTTP_CODE}) : nothing to report on" ; exit 1 ; }

## at a narrow scope only the asked networks are read : the subnets cost one GET per vnet
ASKED=$(printf '%s' "$REQ" | jq -c 'if .networks == null then null else [ .networks[].vnet ] end')

printf '%s' "$BODY" | jq -c --arg a "$ACTION" --arg s "$SOURCE_TAG" --arg n "$NODE" --argjson asked "$ASKED" '
  .data[]?
  | select($asked == null or (.vnet as $v | $asked | index($v)))
  | {
      action:             $a,
      source:             $s,
      proxmox_node:       $n,
      vnet:               .vnet,
      vnet_zone:          .zone,
      vnet_alias:         .alias,
      vnet_tag:           .tag,
      vnet_vlanaware:     .vlanaware,
      vnet_isolate_ports: .["isolate-ports"],
      vnet_pending:       .pending,
      vnet_state:         .state
    }
  | with_entries(select(.value != null))' > "$TMP_DIR/vnets.jsonl"

while IFS= read -r VNET; do
  [[ -n "$VNET" ]] || continue
  _get "${BASE_URL}/cluster/sdn/vnets/${VNET}/subnets"
  if [[ "$HTTP_CODE" != "200" ]]; then
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "cannot read the subnets of vnet ${VNET} (http ${HTTP_CODE}) : it will look like a vnet without subnet"
    continue
  fi
  printf '%s' "$BODY" | jq -c --arg a "$ACTION" --arg s "$SOURCE_TAG" --arg n "$NODE" --arg vnet "$VNET" '
    .data[]?
    | {
        action:                 $a,
        source:                 $s,
        proxmox_node:           $n,
        subnet:                 .subnet,
        subnet_vnet:            $vnet,
        subnet_cidr:            .cidr,
        subnet_type:            .type,
        subnet_zone:            .zone,
        subnet_gateway:         .gateway,
        subnet_snat:            .snat,
        subnet_dhcp_range:      .["dhcp-range"],
        subnet_dhcp_dns_server: .["dhcp-dns-server"],
        subnet_pending:         .pending,
        subnet_state:           .state
      }
    | with_entries(select(.value != null))' >> "$TMP_DIR/subnets.jsonl"
done < <(jq -r '.vnet' "$TMP_DIR/vnets.jsonl")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the live state : NOT an api object, so the ansible reader over SSH, on both paths. A failure here
# does not end the run, it makes the counts unknown.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

_json_only() {
  local l
  while IFS= read -r l ; do
    [ -n "${l//[[:space:]]/}" ] || continue
    printf '%s\n' "$l" | jq -e . >/dev/null 2>&1 && printf '%s\n' "$l"
  done
  return 0
}

set +e
printf '%s\n' '{}' | proxmox_network.datacenter.list_snat_rules.to.jsons.sh --json > "$TMP_DIR/rules_raw" 2>/dev/null
rc=$?
set -e
RULES_OK=true
if [[ "$rc" -ne 0 ]]; then
  RULES_OK=false
  devkit_utils.text.echo_trace.to.text.to.stderr.sh "cannot read the live SNAT rules of the node (rc ${rc}) : the counts stay unknown"
fi
_json_only < "$TMP_DIR/rules_raw" | jq -c 'if type == "array" then .[] else . end' > "$TMP_DIR/rules.jsonl"

proxmox__inc.show_sdn.join.sh \
  "$TMP_DIR/vnets.jsonl" "$TMP_DIR/subnets.jsonl" "$TMP_DIR/rules.jsonl" \
  "$REQ" "$SOURCE_TAG" "$NODE" "$RULES_OK" > "$TMP_DIR/lines"

if [[ "$RULES_OK" != true ]]; then
  jq -n -c --arg action "$ACTION" --arg src "$SOURCE_TAG" --arg node "$NODE" \
    --arg reason "the live SNAT rules reader failed (rc ${rc})" \
    '
    {
      level: "error",
      action: $action,
      source: $src,
      proxmox_node: $node,
      vnet: null,
      reason: $reason
    }' >> "$TMP_DIR/lines"
fi

# the table is titled with the perimeter that was ASKED : a network the sdn does not declare still
# gets a row, so the rows alone do not say what was asked for
LABEL=$(printf '%s' "$REQ" | jq -r '
  if .scope == "scenario" then
    "scenario: " + (.scenario_name // "?")
  elif .scope == "sdn_vnet" then
    (.networks[0].vnet)
  elif .scope == "sdn_vnets" then
    ((.networks | length | tostring) + " networks on stdin")
  else
    "datacenter : every network"
  end')

proxmox__inc.show_sdn.render.sh "$OUTPUT" "$LABEL" < "$TMP_DIR/lines"
