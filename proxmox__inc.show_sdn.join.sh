#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# proxmox__inc.show_sdn.join.sh <vnets.jsonl> <subnets.jsonl> <rules.jsonl> <request> <source> <node> <rules_ok>
#
# THE JOIN OF THE show_sdn VIEW, IN ONE PLACE. The engine and its api twin read the same three
# things through different pipes - the declared vnets, the declared subnets, the live SNAT rules -
# and hand them here as three files of json lines. Everything the view says is computed here, so
# the two paths cannot disagree on a verdict. The rules view learned that the hard way : the same
# calculation written twice ended up naming the causes of a verdict in two different orders.
#
# One line per network of the request, plus - at scope dc and all only - one line per live rule
# whose source network no subnet declares.
#
#   level network      a network the cluster declares (as a vnet, as a subnet, or both)
#   level undeclared   a network that was ASKED and that the SDN does not know : a legacy vmbr
#                      bridge is exactly that, and its live rules still count when a cidr came
#                      with the request
#   level rules_only   a live SNAT rule whose source cidr no declared subnet carries : an egress
#                      nothing in the SDN accounts for
#
# rules_ok is false when the live rules could not be read. Then snat_rules is null and internet
# says "?" rather than "NO" : an unread rule is not an absent rule.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ] || [ "$#" -lt 7 ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - shared join of the show_sdn engine and its twin "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") <vnets.jsonl> <subnets.jsonl> <rules.jsonl> <request json> <source tag> <node> <true|false>"
  echo
  echo "  prints the json lines of the view : levels network, undeclared, rules_only"
  echo
  echo
  exit 1
fi

VNETS="$1"
SUBNETS="$2"
RULES="$3"
REQ="$4"
SOURCE_TAG="$5"
NODE="$6"
RULES_OK="$7"

jq -n -c \
  --slurpfile vnt "$VNETS" \
  --slurpfile sub "$SUBNETS" \
  --slurpfile rul "$RULES" \
  --argjson req "$REQ" \
  --arg src "$SOURCE_TAG" \
  --arg node "$NODE" \
  --argjson rules_ok "$RULES_OK" \
  '
  ## a switch is 0, 1 or absent on both paths : absent means never set, never 0
  def on: (. != null) and ((. | tostring) != "0") and ((. | tostring) != "");

  ## SNAT is written by the SDN post-up hook, MASQUERADE by the legacy bridge stanza. A network
  ## carrying BOTH shapes is named mixed : the reconciliation primitive deletes per source network
  ## and could take the wrong one, so such a network is left alone by every gesture.
  def origin($targets):
    if   ($targets | length) == 0                                             then null
    elif ($targets | index("SNAT")) and ($targets | index("MASQUERADE"))      then "mixed"
    elif ($targets | index("SNAT"))                                          then "sdn"
    elif ($targets | index("MASQUERADE"))                                    then "legacy"
    else ($targets | join(","))
    end;

  ( [ $vnt[] | select(type == "object" and .vnet        != null) ] ) as $vnets
  | ( [ $sub[] | select(type == "object" and .subnet_vnet != null) ] ) as $subs
  | ( [ $rul[] | select(type == "object" and .snat_source != null) ] ) as $rules

  ## the networks of the request, or every network the cluster declares
  | ( if $req.networks == null then
        ( [ ($vnets[] | .vnet), ($subs[] | .subnet_vnet) ]
          | unique
          | map({ vnet: ., cidr: null }) )
      else
        $req.networks
      end ) as $asked

  | ( [ $asked[]
        | . as $a
        | ( [ $vnets[] | select(.vnet        == $a.vnet) ] | first ) as $v
        | ( [ $subs[]  | select(.subnet_vnet == $a.vnet) ] )         as $s_all
        | ( $s_all | first )                                        as $s
        ## the cidrs this network answers for : those of its subnets, plus the one the caller gave
        | ( [ $s_all[] | .subnet_cidr | select(. != null) ] + [ $a.cidr | select(. != null) ]
            | unique )                                              as $cidrs
        | ( ($s.subnet_cidr // $a.cidr) // null )                   as $cidr
        | ( [ $rules[] | select(.snat_source as $x | $cidrs | index($x)) ] ) as $r
        | ( [ $r[] | .snat_count ]    | add // 0 )                  as $count
        | ( [ $r[] | .snat_target ]   | unique )                    as $targets
        | ( [ $r[] | .snat_out_iface ] | unique )                   as $ifaces
        ## a count is unknown, not zero, when the rules could not be read or when no cidr is known
        | ( ($rules_ok | not) or ($cidrs | length) == 0 )           as $unknown
        | {
            level:              (if ($v != null or $s != null) then "network" else "undeclared" end),
            action:             "show_sdn",
            source:             $src,
            proxmox_node:       $node,
            vnet:               $a.vnet,
            cidr:               $cidr,
            zone:               (($s.subnet_zone // $v.vnet_zone) // null),
            subnet:             ($s.subnet         // null),
            subnet_cidr:        ($s.subnet_cidr    // null),
            subnet_gateway:     ($s.subnet_gateway // null),
            subnet_snat:        ($s.subnet_snat    // null),
            subnets:            ($s_all | length),
            vnet_zone:          ($v.vnet_zone          // null),
            vnet_isolate_ports: ($v.vnet_isolate_ports // null),
            ## an absent snat means off, never unknown ; no subnet at all is a third answer
            outgoing_nat:       (if   $s == null                  then "no-subnet"
                                 elif ($s.subnet_snat | on)       then "on"
                                 else                                  "off" end),
            ## an absent isolate-ports means no, same guard as snat
            isolated:           ($v.vnet_isolate_ports | on),
            snat_rules:         (if $unknown then null else $count end),
            snat_origin:        (if $unknown then null else origin($targets) end),
            snat_out_iface:     (if ($ifaces | length) == 0 then null else $ifaces end),
            ## the verdict follows the LIVE rules, not the declaration : a legacy MASQUERADE
            ## forwards just as well, and a subnet at snat=1 that was never applied forwards nothing
            internet:           (if   $unknown   then "?"
                                 elif $count > 0 then "YES"
                                 else                 "NO" end)
          }
      ] ) as $net_lines

  ## at scope dc and all, the live rules nothing declares : an egress the SDN does not account for
  | ( if $req.networks == null and $rules_ok then
        ( [ $subs[] | .subnet_cidr | select(. != null) ] | unique ) as $declared
        | [ $rules
            | group_by(.snat_source)[]
            | select( (.[0].snat_source) as $s | ($declared | index($s)) == null )
            | {
                level:          "rules_only",
                action:         "show_sdn",
                source:         $src,
                proxmox_node:   $node,
                vnet:           null,
                cidr:           .[0].snat_source,
                snat_rules:     ([ .[] | .snat_count ] | add // 0),
                snat_origin:    origin([ .[] | .snat_target ] | unique),
                snat_out_iface: ([ .[] | .snat_out_iface ] | unique),
                internet:       "YES"
              }
          ]
      else [] end ) as $extra_lines

  | ($net_lines + $extra_lines)[]'
