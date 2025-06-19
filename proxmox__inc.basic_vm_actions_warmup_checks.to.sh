#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ARG_ACTION="${1:-}"
ALLOWED_ACTIONS=(
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
  storage_list
  storage_list_iso
  storage_list_template
  network_list_interfaces_vm
  network_list_interfaces_node
  network_list_node_sdn_zones
  snapshot_vm_list
  snapshot_lxc_list
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
