#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox__inc.firewall_chain.sh
#
# The predicates of a firewall chain, and the edit of a network card string : ONE copy,
# SOURCED by the *_with_api twins that guard before they write.
#
#     source proxmox__inc.firewall_chain.sh
#
# The role keeps one copy of these predicates per action file, on purpose (self-contained
# action files). The devkits have includes, so here the copy lives once and the twins call
# it. What it encodes was measured on the role side (2026-08-26 and 27) :
#   - a rule stored without `enable` is disabled by Proxmox and grants nothing ;
#   - the barrier is the FIRST active inbound DROP or REJECT that can reach the port ; a
#     deny covers a port unless its dport is purely numeric AND different (a range, a list,
#     an absent or empty dport all cover : the predicate fails closed) ;
#   - an accept counts only when active AND above that barrier ;
#   - 99999 is the sentinel for "none".
#
# fw_chain_verdict <api_port> <ssh_port>      stdin : the json body of GET .../firewall/rules
#   stdout, one json object :
#     total, active         how many rules the chain holds, how many are active
#     cover_api, cover_ssh  position of the first active deny that reaches that port (99999 : none)
#     api_first, ssh_first  position of the first active accept on that port (99999 : none)
#     has_api, has_ssh      the accept is present, active and above the covering deny
#
# fw_iface_edit <net string> <0|1>             stdout : {"stripped","wanted","already"}
#   the string with any firewall key removed, the string to write, and whether the card
#   already carried the wanted value (nothing to write then). Only the firewall key moves :
#   the MAC, the bridge, the tag, the mtu and any key a future PVE adds stay as they are.
#
# fw_iface_verdict <before> <after> <current> <0|1>
#   stdout : {"mac_before","mac_after","is_set","lost_keys","current_agrees"}
#   the four questions the role asks after the write : the flag is set, the MAC did not
#   change, no key was lost, and the running guest agrees with the stored config (an empty
#   current string means it could not be read, and counts as agreeing, as in the role).
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - LIB / INCLUDE to be SOURCED by the *_with_api twins : the predicates of a firewall chain, the edit of a network card string"
  echo
  echo USAGE
  echo
  echo "  source $(basename "$0")"
  echo "  curl .../firewall/rules | fw_chain_verdict 8006 22        -> {total,active,cover_api,cover_ssh,api_first,ssh_first,has_api,has_ssh}"
  echo "  fw_iface_edit 'virtio=BC:24:11:00:00:01,bridge=net143' 1  -> {stripped,wanted,already}"
  echo "  fw_iface_verdict <before> <after> <current> 1              -> {mac_before,mac_after,is_set,lost_keys,current_agrees}"
  echo
  exit 1
fi

fw_chain_verdict() {
  jq -c --arg api "${1:-8006}" --arg ssh "${2:-22}" '
    def rules: ((.data // []) | if type == "array" then map(select(type == "object")) else [] end);
    def active: select(has("enable") and ((.enable | tostring) != "0"));
    def inbound_deny: select(((.type // "") == "in") and (((.action // "") == "DROP") or ((.action // "") == "REJECT"))) | active | select(has("pos"));
    def inbound_accept($p): select(((.type // "") == "in") and ((.action // "") == "ACCEPT") and has("dport") and ((.dport | tostring) == $p)) | active | select(has("pos"));
    def other_port($p): select(has("dport") and (.dport != null) and ((.dport | tostring) | test("^[0-9]+$")) and ((.dport | tostring) != $p));
    def positions: map(.pos | tonumber);
    def cover($p): (([rules[] | inbound_deny] | positions) - ([rules[] | inbound_deny | other_port($p)] | positions) + [99999]) | min;
    def first_accept($p): (([rules[] | inbound_accept($p)] | positions) + [99999]) | min;
    {
      total: (rules | length),
      active: ([rules[] | active] | length),
      cover_api: cover($api),
      cover_ssh: cover($ssh),
      api_first: first_accept($api),
      ssh_first: first_accept($ssh)
    }
    | .has_api = (.api_first < .cover_api)
    | .has_ssh = (.ssh_first < .cover_ssh)
  '
}

fw_iface_edit() {
  jq -cn --arg s "$1" --arg want "$2" '
    ($s
      | gsub(",firewall=[^,]*"; "")
      | sub("^firewall=[^,]*,"; "")
      | sub("^firewall=[^,]*$"; "")) as $stripped
    | {
        stripped: $stripped,
        wanted: ($stripped + ",firewall=" + $want),
        already: ($s | contains("firewall=" + $want))
      }
  '
}

fw_iface_verdict() {
  jq -cn --arg b "$1" --arg a "$2" --arg c "$3" --arg want "$4" '
    def mac: ([match("([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}")] | if length > 0 then .[0].string else "" end);
    def keys_of: (gsub(",?firewall=[^,]*"; "") | split(",") | map(select(. != "")));
    {
      mac_before: ($b | mac),
      mac_after: ($a | mac),
      is_set: ($a | contains("firewall=" + $want)),
      lost_keys: (($b | keys_of) - ($a | keys_of)),
      current_agrees: ((($c | length) == 0) or ($c | contains("firewall=" + $want)))
    }
  '
}
