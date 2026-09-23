#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox__inc.snat_rules.node.sh
#
# >>> THIS FILE RUNS ON THE HYPERVISOR, NOT ON THE DEPLOYER <<<
# The ssh twins of list_snat_rules and delete_extra_snat_rules copy it to the node
# (scp), run it there (bash <file> list | delete <cidr> <want> ...), and remove it.
# It refuses to run where a range42 workspace is loaded, so a call by mistake on the
# deployer does nothing.
#
# The two functions below are the two `shell:` blocks of the role actions
# network_list_snat_rules and network_delete_extra_snat_rules, CHARACTER FOR CHARACTER,
# the only difference being the two Jinja assignments of the delete block, which became
# the two positional arguments of its function. The commit that ships this file proves
# that identity mechanically, and its live replays the proof before indexing. What runs
# on the hypervisor is therefore what ansible already runs there at every play, minus
# python : iptables, grep, sed, sort, uniq, hostname, printf, and bash.
#
# One session for every network : delete takes pairs, in order, and prints one json line
# per pair, in order. The first refused deletion ends the run with rc 1, as the role does.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -u

if [[ -n "${RANGE42_ANSIBLE_ROLES__DEVKITS_DIR:-}" || -n "${RANGE42_ACTIVE_CONFIG_DIR:-}" ]]; then
  echo "snat_rules.node.sh: this file runs on the hypervisor, the ssh twins send it there. Nothing was done." >&2
  exit 1
fi

# the role runs its blocks under this PATH : iptables lives in /usr/sbin
export PATH="/usr/sbin:/sbin:/usr/bin:/bin"

for b in iptables grep sed sort uniq hostname ; do
  command -v "$b" >/dev/null 2>&1 || {
    echo "snat_rules.node.sh: $b not found on $(hostname 2>/dev/null || echo '?'), nothing was done" >&2
    exit 1
  }
done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the shell block of network_list_snat_rules, verbatim
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

list_snat_rules() {
  set -u

  command -v iptables >/dev/null 2>&1 || {
    echo "list_snat_rules: iptables not found on $(hostname), PATH=$PATH" >&2
    exit 1
  }

  ## captured, and its status checked, so a read failure cannot look like an empty chain
  table=$(iptables -t nat -S POSTROUTING) || {
    echo "list_snat_rules: cannot read the nat table on $(hostname)" >&2
    exit 1
  }

  ## one line per rule that scopes a source network, then grouped by (source, target).
  ## An empty result here means the host carries no such rule, which is a real answer.
  printf '%s\n' "$table" | grep -- ' -s ' | while IFS= read -r line ; do
    src=${line#* -s }
    src=${src%% *}
    ## the OUT INTERFACE : this is the answer to "where does this subnet actually leave
    ## through". Proxmox auto-detects it from the default route when it writes the vnet
    ## hook, so it is not something we declare anywhere - it can only be read here.
    case "$line" in
      *' -o '*) out=${line#* -o } ; out=${out%% *} ;;
      *)        out="any" ;;
    esac
    case "$line" in
      *' -j '*) tgt=${line##* -j } ; tgt=${tgt%% *} ;;
      *)        tgt="none" ;;
    esac
    [ -n "$src" ] && printf '%s %s %s\n' "$src" "$out" "$tgt"
  done | sort | uniq -c | while read -r cnt src out tgt ; do
    printf '{"snat_source":"%s","snat_out_iface":"%s","snat_target":"%s","snat_count":%s}\n' \
      "$src" "$out" "$tgt" "$cnt"
  done
}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# the shell block of network_delete_extra_snat_rules, verbatim but for its two Jinja
# assignments : S and want are the two arguments
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

delete_extra_snat_rules() {
  set -u
  S="$1"
  want="${2:-1}"

  command -v iptables >/dev/null 2>&1 || {
    echo "delete_extra_snat_rules: iptables not found on $(hostname), PATH=$PATH" >&2
    exit 1
  }

  ## counting on captured text, so a read failure cannot look like an empty chain
  table=$(iptables -t nat -S POSTROUTING) || {
    echo "delete_extra_snat_rules: cannot read the nat table on $(hostname)" >&2
    exit 1
  }
  before=$(printf '%s\n' "$table" | grep -c -- "-s ${S} " || true)

  guard=0
  now="$before"
  while [ "$now" -gt "$want" ]; do
    guard=$((guard + 1))
    if [ "$guard" -gt 1000 ]; then
      echo "delete_extra_snat_rules: gave up after 1000 deletions, the rule count is not decreasing" >&2
      exit 1
    fi

    rule=$(printf '%s\n' "$table" | grep -m1 -- "-s ${S} " | sed 's/^-A /-D /')
    if [ -z "$rule" ]; then
      echo "delete_extra_snat_rules: counted ${now} rules but could not extract one to delete" >&2
      exit 1
    fi

    # shellcheck disable=SC2086
    iptables -t nat $rule || {
      echo "delete_extra_snat_rules: deletion refused : ${rule}" >&2
      exit 1
    }

    table=$(iptables -t nat -S POSTROUTING) || {
      echo "delete_extra_snat_rules: cannot re-read the nat table after a deletion" >&2
      exit 1
    }
    now=$(printf '%s\n' "$table" | grep -c -- "-s ${S} " || true)
  done
  after="$now"

  printf '{"before":%s,"after":%s,"want":%s,"deleted":%s}\n' \
    "$before" "$after" "$want" "$((before - after))"
}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

case "${1:-}" in
  list)
    list_snat_rules
    ;;
  delete)
    shift
    if [ "$#" -lt 2 ] || [ $(( $# % 2 )) -ne 0 ]; then
      echo "snat_rules.node.sh: delete takes pairs : <cidr> <want> [<cidr> <want> ...]. Nothing was done." >&2
      exit 1
    fi
    while [ "$#" -ge 2 ]; do
      delete_extra_snat_rules "$1" "$2"
      shift 2
    done
    ;;
  *)
    echo "usage: bash $(basename "$0") list | delete <cidr> <want> [<cidr> <want> ...]" >&2
    exit 1
    ;;
esac
