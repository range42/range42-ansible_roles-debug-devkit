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
  network_list_sdn_zones
  network_list_sdn_vnets
  network_list_sdn_subnets
  network_list_snat_rules
  #
  # SDN cluster-level, dans l'ordre operationnel : creer, modifier, supprimer,
  # appliquer, puis reconcilier les regles SNAT vivantes (l'apply n'est pas idempotent).
  # L'ordre de suppression est impose par Proxmox : subnet -> vnet -> zone.
  network_add_sdn_zone
  network_add_sdn_vnet
  network_add_sdn_subnet
  network_update_sdn_subnet
  network_delete_sdn_subnet
  network_delete_sdn_vnet
  network_delete_sdn_zone
  network_apply_sdn
  network_delete_extra_snat_rules
  #
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
  firewall_vm_iface_enable
  firewall_vm_iface_disable
  #
  firewall_vm_apply_iptables_rule
  firewall_vm_delete_iptables_rule
  firewall_vm_list_iptables_rule
  #
  firewall_vm_add_iptables_alias
  firewall_vm_delete_iptables_alias
  firewall_vm_list_iptables_alias
  #
  firewall_vm_enable_default_ssh_rules
  firewall_vm_declare_iptables_port
  #
  firewall_node_enable
  firewall_node_disable
  firewall_node_apply_iptables_rule
  firewall_node_list_iptables_rule
  firewall_node_delete_iptables_rule
  # anti-lockout : a jouer AVANT firewall_node_enable, jamais apres
  firewall_node_enable_management_access
  #
  firewall_dc_enable
  firewall_dc_disable
  firewall_dc_list_iptables_rule
  firewall_dc_apply_iptables_rule
  firewall_dc_delete_iptables_rule
  # LECTURE des options, aux trois niveaux. Elle manquait partout : le role ne savait que
  # PUT l'interrupteur, jamais le GET, donc aucune ecriture n'etait idempotente et aucun
  # assert ne pouvait verifier sa premisse. Un enable lu ici est une condition necessaire,
  # jamais suffisante : sans le flag de la carte, rien n'est filtre.
  firewall_dc_list_options
  firewall_node_list_options
  firewall_vm_list_options
  # alias du DATACENTER : un alias est un objet cluster-wide et par invite, l'api n'en
  # expose aucun au niveau d'un noeud. Un alias datacenter est deja visible des regles
  # de chaque noeud, donc il n'y a rien qu'un alias de noeud pourrait cadrer.
  firewall_dc_list_iptables_alias
  firewall_dc_add_iptables_alias
  firewall_dc_delete_iptables_alias
  # anti-lockout du DATACENTER : le niveau retenu, il couvre tout noeud a venir sans
  # qu'on ait a le rejouer. A lancer AVANT toute activation, jamais apres.
  firewall_dc_enable_management_access
  #
  cluster_set_tag
  #
  template_create
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
