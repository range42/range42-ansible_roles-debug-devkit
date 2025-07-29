#!/bin/bash

#
# PR-25
#

set -euo pipefail

ARG_ACTION="${1:-}"
ALLOWED_ACTIONS=(
  vm_create
  vm_delete
  #
  vm_pause
  vm_resume
  vm_start
  vm_stop
  vm_stop_force
  vm_list
  vm_list_usage
  #
  vm_clone
  #
  vm_get_config
  vm_get_config_cdrom
  vm_get_config_ram
  vm_get_config_cpu
  vm_get_usage
  vm_set_tag
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  lxc_create
  lxc_delete
  #
  lxc_pause
  lxc_resume
  lxc_start
  lxc_stop
  lxc_stop_force
  #
  lxc_clone
  #
  lxc_list
  lxc_set_tag
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  storage_list
  storage_list_iso
  storage_download_iso
  storage_list_template

  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  network_list_interfaces_vm
  network_list_interfaces_node
  network_list_node_sdn_zones
  network_add_interfaces_vm
  network_delete_interfaces_vm
  network_add_interfaces_node
  network_delete_interfaces_node
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
  #
  firewall_vm_apply_iptables_rule
  firewall_vm_delete_iptables_rule
  firewall_vm_list_iptables_rule
  #
  firewall_vm_add_iptables_alias
  firewall_vm_delete_iptables_alias
  firewall_vm_list_iptables_alias
  firewall_node_enable
  firewall_dc_enable
  #
  cluster_set_tag
  #
  template_convert_vm_to_template
  template_cloudinit_import_disk
  cloudinit_set_variables

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
