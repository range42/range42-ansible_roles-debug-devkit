#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox__inc.ssh_node.sh
#
# The hypervisor over SSH, for the *_with_ssh twins : the two iptables actions have no api
# (network_list_snat_rules, network_delete_extra_snat_rules), the role runs them as shell
# on the node through the `proxmox_cli` group of the inventory. The twins reach the SAME
# host the same way : the first host of that group, resolved by ssh exactly as ansible
# resolves it (the deployer's ssh configuration ; the inventory vars when it carries some).
#
# >>> THIS FILE IS SOURCED, NOT EXECUTED <<<
#
#     source proxmox__inc.ssh_node.sh
#
# IT SETS : SSH_HOST (the inventory name of the node), SSH_TARGET (what ssh is given :
#           the name, or user@ansible_host), SSH_OPTS (BatchMode, a short connect timeout,
#           the port and the key when the inventory names them), NODE_SCRIPT (the local
#           path of proxmox__inc.snat_rules.node.sh, the one file that goes to the node).
#
# IT DEFINES :
#           _ssh_probe                 rc 0 when the node answers `true` over ssh, silent, and
#                                      without touching the caller's stdin (ssh -n)
#           _node_script_run <args>    copies the node script to /tmp on the node, runs it
#                                      there with the arguments, removes it, in one session
#                                      after the copy. NODE_OUT : what the script printed.
#                                      NODE_RC : its exit status. NODE_ERR : its stderr.
#                                      Call it plainly, never inside $(...) : a subshell
#                                      would keep the three variables for itself.
#                                      Every argument must be a word of [A-Za-z0-9./] :
#                                      anything else is refused before any connection.
#
# IT EXITS the caller (rc 1) when the inventory of the active workspace, its proxmox_cli
# group or the node script cannot be found. The context guard is NOT here : every twin
# runs proxmox__inc.warmup_checks.sh first, on purpose.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - LIB / INCLUDE to be SOURCED by the *_with_ssh twins : the hypervisor over ssh, as the inventory declares it"
  echo
  echo USAGE
  echo
  echo "  source $(basename "$0")      # inside a twin, right after proxmox__inc.warmup_checks.sh"
  echo
  echo "  sets    : SSH_HOST SSH_TARGET SSH_OPTS NODE_SCRIPT"
  echo "  defines : _ssh_probe   _node_script_run <args...>   (NODE_OUT, NODE_RC, NODE_ERR)"
  echo
  exit 1
fi

if [[ -z "${RANGE42_ANSIBLE_ROLES__INVENTORY_DIR:-}" ]]; then
  echo "ERROR: RANGE42_ANSIBLE_ROLES__INVENTORY_DIR is not set. Activate a workspace first (range42-context use ...)." >&2
  exit 1
fi

SSH_INVENTORY="${RANGE42_ANSIBLE_ROLES__INVENTORY_DIR%/}/inventory_default.yml"
[[ -r "$SSH_INVENTORY" ]] || { echo "ERROR: inventory not readable: $SSH_INVENTORY" >&2 ; exit 1 ; }

# the inventory as json, once ; the proxmox_cli group wherever it sits in the tree
SSH_INVENTORY_JSON="$(yq -c . "$SSH_INVENTORY" 2>/dev/null || true)"
[[ -n "$SSH_INVENTORY_JSON" ]] || { echo "ERROR: cannot read the inventory as yaml: $SSH_INVENTORY" >&2 ; exit 1 ; }

SSH_HOST="$(printf '%s' "$SSH_INVENTORY_JSON" | jq -r '[.. | objects | select(has("proxmox_cli")) | .proxmox_cli.hosts? | select(. != null) | keys[]] | first // empty')"
if [[ -z "$SSH_HOST" ]]; then
  echo "ERROR: the inventory declares no host in the proxmox_cli group, so there is no hypervisor to reach over ssh (the role would refuse the same way)." >&2
  exit 1
fi

SSH_HOST_VARS="$(printf '%s' "$SSH_INVENTORY_JSON" | jq -c --arg h "$SSH_HOST" '[.. | objects | select(has("proxmox_cli")) | .proxmox_cli.hosts[$h]? | select(. != null)] | first // {}')"
SSH_ANSIBLE_HOST="$(printf '%s' "$SSH_HOST_VARS" | jq -r '.ansible_host // empty')"
SSH_ANSIBLE_USER="$(printf '%s' "$SSH_HOST_VARS" | jq -r '.ansible_user // empty')"
SSH_ANSIBLE_PORT="$(printf '%s' "$SSH_HOST_VARS" | jq -r '.ansible_port // empty')"
SSH_ANSIBLE_KEY="$(printf '%s' "$SSH_HOST_VARS" | jq -r '.ansible_ssh_private_key_file // empty')"

SSH_TARGET="$SSH_HOST"
[[ -n "$SSH_ANSIBLE_HOST" ]] && SSH_TARGET="$SSH_ANSIBLE_HOST"
[[ -n "$SSH_ANSIBLE_USER" ]] && SSH_TARGET="${SSH_ANSIBLE_USER}@${SSH_TARGET}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR)
[[ -n "$SSH_ANSIBLE_PORT" ]] && SSH_OPTS+=(-p "$SSH_ANSIBLE_PORT")
[[ -n "$SSH_ANSIBLE_KEY"  ]] && SSH_OPTS+=(-i "${SSH_ANSIBLE_KEY/#\~/$HOME}")

NODE_SCRIPT="$(command -v proxmox__inc.snat_rules.node.sh || true)"
[[ -n "$NODE_SCRIPT" && -r "$NODE_SCRIPT" ]] || { echo "ERROR: proxmox__inc.snat_rules.node.sh not found on PATH : the ssh twins have nothing to send to the node." >&2 ; exit 1 ; }

# ssh forwards the caller's stdin to the remote command : the probe runs in the facade BEFORE the twin
# and would eat the json lines the twin is about to read. -n takes stdin from /dev/null, always.
_ssh_probe() {
  ssh -n "${SSH_OPTS[@]}" "$SSH_TARGET" true >/dev/null 2>&1
}

_node_script_run() {
  local a remote scp_opts=() err rc
  for a in "$@" ; do
    if ! [[ "$a" =~ ^[A-Za-z0-9./]+$ ]]; then
      NODE_RC=1 ; NODE_OUT="" ; NODE_ERR="refused argument for the node script : '${a}' (only letters, digits, dots and slashes travel)"
      return 1
    fi
  done
  remote="/tmp/range42-snat-rules.$$.${RANDOM}.sh"
  # scp spells the port option in upper case
  for a in "${SSH_OPTS[@]}" ; do scp_opts+=("$a") ; done
  [[ -n "$SSH_ANSIBLE_PORT" ]] && { scp_opts=(-o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR -P "$SSH_ANSIBLE_PORT") ; [[ -n "$SSH_ANSIBLE_KEY" ]] && scp_opts+=(-i "${SSH_ANSIBLE_KEY/#\~/$HOME}") ; }
  err="$(mktemp)"
  if ! scp -q "${scp_opts[@]}" "$NODE_SCRIPT" "${SSH_TARGET}:${remote}" 2>"$err" ; then
    NODE_RC=255 ; NODE_OUT="" ; NODE_ERR="cannot copy the node script to ${SSH_TARGET}:${remote} : $(tr '\n' ' ' < "$err")" ; rm -f "$err" ; return 1
  fi
  # run then remove, whatever the run's status : one command, one session
  NODE_OUT="$(ssh -n "${SSH_OPTS[@]}" "$SSH_TARGET" "bash '${remote}' $* ; rc=\$? ; rm -f '${remote}' ; exit \$rc" 2>"$err")"
  rc=$?
  NODE_RC=$rc
  NODE_ERR="$(tr '\n' ' ' < "$err")"
  rm -f "$err"
  return $rc
}
