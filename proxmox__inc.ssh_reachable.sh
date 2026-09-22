#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# proxmox__inc.ssh_reachable.sh
#
# Probe the hypervisor over ssh, the way proxmox__inc.api_reachable.sh probes the api.
# Exits 0 : the first host of the proxmox_cli group answers `true` over ssh, non
#           interactively (BatchMode), within five seconds.
# Exits 1 : any other case (no workspace, no inventory, no proxmox_cli host, no node
#           script on PATH, connection refused or timed out, key not accepted).
#
# Silent on stdout and stderr ; the caller logs via echo_trace.
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

[[ -n "${RANGE42_ANSIBLE_ROLES__INVENTORY_DIR:-}" ]] || exit 1

# the include exits 1 by itself when the inventory or the node script is missing
source proxmox__inc.ssh_node.sh 2>/dev/null || exit 1

_ssh_probe || exit 1
exit 0
