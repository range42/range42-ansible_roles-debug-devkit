#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ARG_ACTION="${1:-}"
ALLOWED_ACTIONS=(
  vm_create
  vm_delete
  vm_pause
  vm_resume
  vm_start
  vm_stop
  vm_stop_force
  vm_list
  vm_list_usage
  vm_get_config
  vm_get_config_cdrom
  vm_get_config_ram
  vm_get_config_cpu
  vm_get_usage
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  lxc_list
  lxc_delete
  lxc_create
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  storage_list
  storage_list_iso
  storage_list_template
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  network_list_interfaces_vm
  network_list_interfaces_node
  network_list_node_sdn_zones
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  snapshot_vm_create
  snapshot_vm_delete
  snapshot_vm_list
  snapshot_vm_revert
  #
  snapshot_lxc_create
  snapshot_lxc_delete
  snapshot_lxc_list
  snapshot_lxc_revert
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  firewall_vm_enable
  firewall_vm_disable
  firewall_node_enable
  firewall_dc_enable

)

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Warmup checks - check for vm_actions_*"
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ -z "$ARG_ACTION" ]]; then
  devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
  # show_example
  exit 1
else

  #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
  #
  # quick an dirty - i want avoid the switch case.

  valid=false

  for action in "${ALLOWED_ACTIONS[@]}"; do

    if [[ "$ARG_ACTION" == "$action" ]]; then
      valid=true
      break
    fi

  done

  if [ "$valid" = false ]; then

    devkit_utils.text.echo_error.to.text.to.stderr.sh "Invalid action - '$ARG_ACTION'"

    for action in "${ALLOWED_ACTIONS[@]}"; do
      devkit_utils.text.echo_error.to.text.to.stderr.sh " - allowed - '$action'"
    done
    exit 1
  fi

fi
