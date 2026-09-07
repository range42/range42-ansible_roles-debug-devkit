#!/bin/bash

#
# PR-25
#

show_example() {
  echo "  echo 'px-testing' | $(basename "$0") network_list_interfaces_node"

}

if [ "$1" = '-h' ] ||
  [ "$1" = '--help' ]; then
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - LIB / INCLUDE script providing basic generic helper "
  echo
  echo OPTIONS
  echo
  echo "                    $(basename "$0") [-h|--help] "
  echo "  STDIN :: [JSON] | $(basename "$0") [--json]    - force output as json *default "
  echo "  STDIN :: [JSON] | $(basename "$0") [--text]    - force output as text"
  echo ""
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

EXTRA_VAR=""
DEBUG=true
# DEBUG=false

inject_yaml_var() {
  local KEY="$1"
  local VALUE="$2"
  local INDENTATION="              " # 8 spaces

  VALUE="${VALUE//\"/\\\"}" # escaping.

  #
  # FORMAT YAML AND CONTENT TO EXTRA_VAR
  #

  # EXTRA_VAR+="${IDENTATION}${KEY}: \"${VALUE}\"\n"
  EXTRA_VAR+=$(printf '\n%s%s: "%s"\n' "$INDENTATION" "$KEY" "$VALUE")
}

assign_if_not_empty() {
  local KEY_NAME="$1"
  local JSON_LINE="$2"
  local JQ_EXPR="$3"

  local NEW_VALUE

  NEW_VALUE=$(

    printf "%s\n" "$JSON_LINE" |
      jq -r "$JQ_EXPR // empty"
  )

  # vm_id=$(echo "$line" | jq -r '.vm_id // empty')

  if [ -n "$NEW_VALUE" ]; then
    eval "$KEY_NAME=\"\$NEW_VALUE\""
    inject_yaml_var "$KEY_NAME" "$NEW_VALUE"
  fi

}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ROLE_NAME="range42-ansible_roles-proxmox_controller"
DEFAULT_OPEN_VAULT_PW_FILE_PATH="${RANGE42_VAULT_PASSWORD_FILE:-/tmp/vault/vault_pass.txt}"
# CURRENT_ANSIBLE_CONFIG="./ansible_no_skipped_json.cfg"
# CURRENT_ANSIBLE_CONFIG="$RANGE42_ANSIBLE_ROLES__DEVKITS_DIR/ansible_no_skipped_json.cfg"
# CURRENT_ANSIBLE_CONFIG="./ansible.cfg"
CURRENT_ANSIBLE_CONFIG="$RANGE42_ANSIBLE_ROLES__DEVKITS_DIR/ansible.cfg"

ARG_ACTION="${1:-}"
# ARG_NODE_NAME="${2:-}"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh
proxmox__inc.basic_vm_actions_warmup_checks.to.sh "$ARG_ACTION"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# open vault - look for ansible-agent
#

if [[ -f $DEFAULT_OPEN_VAULT_PW_FILE_PATH ]]; then
  ANSIBLE_VAULT_ARG=(--vault-password-file "$DEFAULT_OPEN_VAULT_PW_FILE_PATH")

else

  OPEN_VAULT_PW_FILE_PATH=$(devkit_ansible.open_vault.to.file.sh)
  ANSIBLE_VAULT_ARG=(--vault-password-file "$OPEN_VAULT_PW_FILE_PATH")

fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# inline playbook execution
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

ANSIBLE_CONFIG="$CURRENT_ANSIBLE_CONFIG"
INVENTORY="$RANGE42_ANSIBLE_ROLES__INVENTORY_DIR/inventory_default.yml"
VAULT_ARGS=("${ANSIBLE_VAULT_ARG[@]}")

PLAYBOOK_VARS_FILE="$RANGE42_ANSIBLE_ROLES__DEVKITS_DIR/secrets/default_vault.yml"

IFS=$'\n'

# IS STDIN ?
if [ ! -t 0 ]; then

  # devkit_utils.text.echo_trace.to.text.to.stderr.sh "IT IS STDIN "

  STDIN_DATA=$(cat -)

  IFS=$'\n'

  for line in $STDIN_DATA; do

    if printf "%s\n" "$line" | jq -e 'type == "object"' >/dev/null 2>&1; then

      # devkit_utils.text.echo_trace.to.text.to.stderr.sh ":: JSON_LINE DETECTED :: GET DATA FROM STDIN "

      assign_if_not_empty "proxmox_node" "$line" ".proxmox_node"
      assign_if_not_empty "vm_id" "$line" ".vm_id"
      assign_if_not_empty "storage_name" "$line" ".storage_name"

      assign_if_not_empty "vm_name" "$line" ".vm_name"
      assign_if_not_empty "vm_snapshot_name" "$line" ".vm_snapshot_name"
      assign_if_not_empty "vm_snapshot_description" "$line" ".vm_snapshot_description"

      assign_if_not_empty "lxc_name" "$line" ".lxc_name"
      assign_if_not_empty "lxc_snapshot_name" "$line" ".lxc_snapshot_name"
      assign_if_not_empty "lxc_snapshot_description" "$line" ".lxc_snapshot_description"

      # assign_if_not_empty "vm_id""$line" ".vm_id"
      # assign_if_not_empty "vm_name""$line" ".vm_name"
      assign_if_not_empty "vm_cpu" "$line" ".vm_cpu"
      assign_if_not_empty "vm_cores" "$line" ".vm_cores"
      assign_if_not_empty "vm_sockets" "$line" ".vm_sockets"
      assign_if_not_empty "vm_memory" "$line" ".vm_memory"
      assign_if_not_empty "vm_disk_size" "$line" ".vm_disk_size"
      assign_if_not_empty "vm_iso_file" "$line" ".vm_iso_file"

      ##################################

      assign_if_not_empty "lxc_bridge" "$line" ".lxc_bridge"
      assign_if_not_empty "lxc_cores" "$line" ".lxc_cores"
      assign_if_not_empty "lxc_disk_size" "$line" ".vm_lxc_disk_sizecpu"
      assign_if_not_empty "lxc_dns_primary" "$line" ".lxc_dns_primary"
      assign_if_not_empty "lxc_dns_secondary" "$line" ".lxc_dns_secondary"
      assign_if_not_empty "lxc_gateway" "$line" ".lxc_gateway"
      assign_if_not_empty "lxc_ip" "$line" ".lxc_ip"
      assign_if_not_empty "lxc_memory" "$line" ".lxc_memory"

      assign_if_not_empty "lxc_net_name" "$line" ".lxc_net_name"
      assign_if_not_empty "lxc_password" "$line" ".lxc_password"
      assign_if_not_empty "lxc_ssh_pubkeys" "$line" ".lxc_ssh_pubkeys"
      assign_if_not_empty "lxc_template" "$line" ".lxc_template"
      assign_if_not_empty "lxc_disk_size" "$line" ".lxc_disk_size"

      assign_if_not_empty "proxmox_storage" "$line" ".proxmox_storage"

      # lxc|vm clone
      assign_if_not_empty "vm_new_id" "$line" ".vm_new_id"
      assign_if_not_empty "lxc_description" "$line" ".lxc_description"
      assign_if_not_empty "vm_description" "$line" ".vm_description"

      # storage_download_iso
      assign_if_not_empty "iso_file_content_type" "$line" ".iso_file_content_type"
      assign_if_not_empty "iso_file_name" "$line" ".iso_file_name"
      assign_if_not_empty "iso_url" "$line" ".iso_url"
      #cloud init
      assign_if_not_empty "cloudinit_image_path" "$line" ".cloudinit_image_path"

      # bonus  // extra
      assign_if_not_empty "proxmox_cluster_color_mapping" "$line" ".proxmox_cluster_color_mapping"
      assign_if_not_empty "vm_tag_name" "$line" ".vm_tag_name"
      assign_if_not_empty "lxc_tag_name" "$line" ".lxc_tag_name"

      # fw

      assign_if_not_empty "vm_fw_action" "$line" ".vm_fw_action"
      assign_if_not_empty "vm_fw_type" "$line" ".vm_fw_type"
      assign_if_not_empty "vm_fw_iface" "$line" ".vm_fw_iface"
      assign_if_not_empty "vm_fw_source" "$line" ".vm_fw_source"
      assign_if_not_empty "vm_fw_dest" "$line" ".vm_fw_dest"
      assign_if_not_empty "vm_fw_proto" "$line" ".vm_fw_proto"
      assign_if_not_empty "vm_fw_dport" "$line" ".vm_fw_dport"
      assign_if_not_empty "vm_fw_sport" "$line" ".vm_fw_sport"
      assign_if_not_empty "vm_fw_enable" "$line" ".vm_fw_enable"
      assign_if_not_empty "vm_fw_comment" "$line" ".vm_fw_comment"
      assign_if_not_empty "vm_fw_pos" "$line" ".vm_fw_pos"
      assign_if_not_empty "vm_fw_log" "$line" ".vm_fw_log"

      # fw - the log readers take four optional paging keys per level, and the ssh port of
      # the reachability assert is a parameter : undeclared here, they were silently dropped
      # between the wrapper and the playbook - the help advertised them, nothing arrived.
      assign_if_not_empty "vm_fw_log_limit" "$line" ".vm_fw_log_limit"
      assign_if_not_empty "vm_fw_log_start" "$line" ".vm_fw_log_start"
      assign_if_not_empty "vm_fw_log_since" "$line" ".vm_fw_log_since"
      assign_if_not_empty "vm_fw_log_until" "$line" ".vm_fw_log_until"
      assign_if_not_empty "node_fw_log_limit" "$line" ".node_fw_log_limit"
      assign_if_not_empty "node_fw_log_start" "$line" ".node_fw_log_start"
      assign_if_not_empty "node_fw_log_since" "$line" ".node_fw_log_since"
      assign_if_not_empty "node_fw_log_until" "$line" ".node_fw_log_until"
      assign_if_not_empty "vm_fw_ssh_port" "$line" ".vm_fw_ssh_port"

      # fw - vm level - default ssh rules
      #
      # The action has a default for each of these four, so an undeclared key does not
      # crash it, it silently keeps the default instead of the value the caller passed.

      assign_if_not_empty "vm_fw_ssh_accept_pos" "$line" ".vm_fw_ssh_accept_pos"
      assign_if_not_empty "vm_fw_mgmt_source" "$line" ".vm_fw_mgmt_source"
      assign_if_not_empty "vm_fw_ssh_accept_comment" "$line" ".vm_fw_ssh_accept_comment"
      assign_if_not_empty "vm_fw_drop_all_pos" "$line" ".vm_fw_drop_all_pos"
      assign_if_not_empty "vm_fw_drop_all_comment" "$line" ".vm_fw_drop_all_comment"

      # fw - alias

      assign_if_not_empty "vm_fw_alias_cidr" "$line" ".vm_fw_alias_cidr"
      assign_if_not_empty "vm_fw_alias_name" "$line" ".vm_fw_alias_name"
      assign_if_not_empty "vm_fw_alias_comment" "$line" ".vm_fw_alias_comment"

      # fw - node level
      #
      # Every key an action consumes MUST be declared here, otherwise it is dropped
      # between the JSON line and the playbook and the action fails on an undefined
      # variable. Adding an action to the allowed list is not enough : its PARAMETERS
      # have to be declared too, and in BOTH helpers of this family : the json one and
      # this text one are two independent lists, a key added to only one makes the
      # action work in one output mode and fail in the other.

      assign_if_not_empty "node_fw_action" "$line" ".node_fw_action"
      assign_if_not_empty "node_fw_type" "$line" ".node_fw_type"
      assign_if_not_empty "node_fw_iface" "$line" ".node_fw_iface"
      assign_if_not_empty "node_fw_source" "$line" ".node_fw_source"
      assign_if_not_empty "node_fw_dest" "$line" ".node_fw_dest"
      assign_if_not_empty "node_fw_proto" "$line" ".node_fw_proto"
      assign_if_not_empty "node_fw_dport" "$line" ".node_fw_dport"
      assign_if_not_empty "node_fw_sport" "$line" ".node_fw_sport"
      assign_if_not_empty "node_fw_enable" "$line" ".node_fw_enable"
      assign_if_not_empty "node_fw_comment" "$line" ".node_fw_comment"
      assign_if_not_empty "node_fw_pos" "$line" ".node_fw_pos"
      assign_if_not_empty "node_fw_log" "$line" ".node_fw_log"

      # fw - node level - anti-lockout

      assign_if_not_empty "node_fw_api_port" "$line" ".node_fw_api_port"
      assign_if_not_empty "node_fw_api_pos" "$line" ".node_fw_api_pos"
      assign_if_not_empty "node_fw_api_comment" "$line" ".node_fw_api_comment"
      assign_if_not_empty "node_fw_ssh_port" "$line" ".node_fw_ssh_port"
      assign_if_not_empty "node_fw_ssh_pos" "$line" ".node_fw_ssh_pos"
      assign_if_not_empty "node_fw_ssh_comment" "$line" ".node_fw_ssh_comment"
      assign_if_not_empty "node_fw_mgmt_source" "$line" ".node_fw_mgmt_source"

      # fw - datacenter level
      #
      # Meme regle qu'au-dessus : toute cle qu'une action consomme DOIT etre declaree ici,
      # sinon elle est jetee entre la ligne JSON et le playbook. Et elle doit l'etre dans les
      # DEUX normaliseurs, sinon le chemin --text la perd en silence.

      assign_if_not_empty "dc_fw_action" "$line" ".dc_fw_action"
      assign_if_not_empty "dc_fw_type" "$line" ".dc_fw_type"
      assign_if_not_empty "dc_fw_iface" "$line" ".dc_fw_iface"
      assign_if_not_empty "dc_fw_source" "$line" ".dc_fw_source"
      assign_if_not_empty "dc_fw_dest" "$line" ".dc_fw_dest"
      assign_if_not_empty "dc_fw_proto" "$line" ".dc_fw_proto"
      assign_if_not_empty "dc_fw_dport" "$line" ".dc_fw_dport"
      assign_if_not_empty "dc_fw_sport" "$line" ".dc_fw_sport"
      assign_if_not_empty "dc_fw_enable" "$line" ".dc_fw_enable"
      assign_if_not_empty "dc_fw_comment" "$line" ".dc_fw_comment"
      assign_if_not_empty "dc_fw_log" "$line" ".dc_fw_log"
      assign_if_not_empty "dc_fw_pos" "$line" ".dc_fw_pos"
      assign_if_not_empty "dc_fw_api_port" "$line" ".dc_fw_api_port"
      assign_if_not_empty "dc_fw_ssh_port" "$line" ".dc_fw_ssh_port"
      assign_if_not_empty "dc_fw_api_pos" "$line" ".dc_fw_api_pos"
      assign_if_not_empty "dc_fw_ssh_pos" "$line" ".dc_fw_ssh_pos"
      assign_if_not_empty "dc_fw_alias_name" "$line" ".dc_fw_alias_name"
      assign_if_not_empty "dc_fw_alias_cidr" "$line" ".dc_fw_alias_cidr"
      assign_if_not_empty "dc_fw_alias_comment" "$line" ".dc_fw_alias_comment"
      assign_if_not_empty "dc_fw_opt_enable" "$line" ".dc_fw_opt_enable"
      assign_if_not_empty "dc_fw_opt_policy_in" "$line" ".dc_fw_opt_policy_in"
      assign_if_not_empty "dc_fw_opt_policy_out" "$line" ".dc_fw_opt_policy_out"
      assign_if_not_empty "dc_fw_opt_ebtables" "$line" ".dc_fw_opt_ebtables"
      assign_if_not_empty "dc_fw_opt_log_ratelimit" "$line" ".dc_fw_opt_log_ratelimit"
      assign_if_not_empty "node_fw_opt_enable" "$line" ".node_fw_opt_enable"
      assign_if_not_empty "node_fw_opt_log_level_in" "$line" ".node_fw_opt_log_level_in"
      assign_if_not_empty "node_fw_opt_log_level_out" "$line" ".node_fw_opt_log_level_out"
      assign_if_not_empty "node_fw_opt_nosmurfs" "$line" ".node_fw_opt_nosmurfs"
      assign_if_not_empty "node_fw_opt_tcpflags" "$line" ".node_fw_opt_tcpflags"
      assign_if_not_empty "node_fw_opt_ndp" "$line" ".node_fw_opt_ndp"
      assign_if_not_empty "node_fw_opt_nf_conntrack_max" "$line" ".node_fw_opt_nf_conntrack_max"
      assign_if_not_empty "node_fw_opt_protection_synflood" "$line" ".node_fw_opt_protection_synflood"
      assign_if_not_empty "vm_fw_opt_enable" "$line" ".vm_fw_opt_enable"
      assign_if_not_empty "vm_fw_opt_policy_in" "$line" ".vm_fw_opt_policy_in"
      assign_if_not_empty "vm_fw_opt_policy_out" "$line" ".vm_fw_opt_policy_out"
      assign_if_not_empty "vm_fw_opt_ipfilter" "$line" ".vm_fw_opt_ipfilter"
      assign_if_not_empty "vm_fw_opt_macfilter" "$line" ".vm_fw_opt_macfilter"
      assign_if_not_empty "vm_fw_opt_dhcp" "$line" ".vm_fw_opt_dhcp"
      assign_if_not_empty "vm_fw_opt_ndp" "$line" ".vm_fw_opt_ndp"
      assign_if_not_empty "vm_fw_opt_radv" "$line" ".vm_fw_opt_radv"
      assign_if_not_empty "vm_fw_opt_log_level_in" "$line" ".vm_fw_opt_log_level_in"
      assign_if_not_empty "vm_fw_opt_log_level_out" "$line" ".vm_fw_opt_log_level_out"
      assign_if_not_empty "dc_fw_mgmt_source" "$line" ".dc_fw_mgmt_source"
      assign_if_not_empty "dc_fw_api_comment" "$line" ".dc_fw_api_comment"
      assign_if_not_empty "dc_fw_ssh_comment" "$line" ".dc_fw_ssh_comment"

      # sdn - zone

      assign_if_not_empty "sdn_zone" "$line" ".sdn_zone"
      assign_if_not_empty "sdn_zone_type" "$line" ".sdn_zone_type"
      assign_if_not_empty "sdn_zone_nodes" "$line" ".sdn_zone_nodes"
      assign_if_not_empty "sdn_zone_mtu" "$line" ".sdn_zone_mtu"
      assign_if_not_empty "sdn_zone_dhcp" "$line" ".sdn_zone_dhcp"

      # sdn - vnet

      assign_if_not_empty "sdn_vnet" "$line" ".sdn_vnet"
      assign_if_not_empty "sdn_vnet_alias" "$line" ".sdn_vnet_alias"
      assign_if_not_empty "sdn_vnet_tag" "$line" ".sdn_vnet_tag"
      assign_if_not_empty "sdn_vnet_vlanaware" "$line" ".sdn_vnet_vlanaware"
      assign_if_not_empty "sdn_vnet_isolate_ports" "$line" ".sdn_vnet_isolate_ports"

      # sdn - subnet
      #
      # sdn_subnet is the CIDR, used on creation. sdn_subnet_id is the id Proxmox derives
      # from it, <zone>-<network>-<mask>, and is what an update or a delete addresses.
      # Two distinct keys on purpose : passing one where the other is expected fails.

      assign_if_not_empty "sdn_subnet" "$line" ".sdn_subnet"
      assign_if_not_empty "sdn_subnet_id" "$line" ".sdn_subnet_id"
      assign_if_not_empty "sdn_subnet_cidr" "$line" ".sdn_subnet_cidr"
      assign_if_not_empty "sdn_subnet_type" "$line" ".sdn_subnet_type"
      assign_if_not_empty "sdn_subnet_gateway" "$line" ".sdn_subnet_gateway"
      assign_if_not_empty "sdn_subnet_snat" "$line" ".sdn_subnet_snat"
      assign_if_not_empty "sdn_subnet_dhcp_range" "$line" ".sdn_subnet_dhcp_range"
      assign_if_not_empty "sdn_subnet_dhcp_dns_server" "$line" ".sdn_subnet_dhcp_dns_server"

      # sdn - apply polling and snat reconciliation

      assign_if_not_empty "sdn_apply_poll_retries" "$line" ".sdn_apply_poll_retries"
      assign_if_not_empty "sdn_apply_poll_delay" "$line" ".sdn_apply_poll_delay"
      assign_if_not_empty "sdn_snat_want" "$line" ".sdn_snat_want"

      # net iface - vm
      assign_if_not_empty "iface_model" "$line" ".iface_model"
      assign_if_not_empty "iface_bridge" "$line" ".iface_bridge"

      ## Consumed by add_network_vm behind an "is defined". Undeclared here, the key is read
      ## then dropped and the caller gets no error : the parameter is simply unreachable.
      ## Five of this group stay closed (tag, queues, rate, trunks, model_mac).
      ##
      ## iface_macaddr is open because its absence CUTS guests, measured : changing a card
      ## attribute means delete then add, and without it the add cannot resend the MAC.
      ## Proxmox draws a new one, the netplan match on macaddress fails, and the guest loses
      ## its network with nothing showing on the Proxmox side.
      assign_if_not_empty "iface_firewall" "$line" ".iface_firewall"
      assign_if_not_empty "iface_macaddr" "$line" ".iface_macaddr"
      assign_if_not_empty "iface_link_down" "$line" ".iface_link_down"
      assign_if_not_empty "vm_vmnet_id" "$line" ".vm_vmnet_id"

      # net iface - node
      assign_if_not_empty "iface_name" "$line" ".iface_name"
      assign_if_not_empty "iface_type" "$line" ".iface_type"
      assign_if_not_empty "iface_autostart" "$line" ".iface_autostart"
      assign_if_not_empty "iface_mtu" "$line" ".iface_mtu"
      assign_if_not_empty "iface_vlan_id" "$line" ".iface_vlan_id"
      assign_if_not_empty "iface_vlan_raw_device" "$line" ".iface_vlan_raw_device"
      assign_if_not_empty "ip_address" "$line" ".ip_address"
      assign_if_not_empty "ip_cidr" "$line" ".ip_cidr"
      assign_if_not_empty "ip_gateway" "$line" ".ip_gateway"
      assign_if_not_empty "ip_netmask" "$line" ".ip_netmask"
      assign_if_not_empty "ip_comments" "$line" ".ip_comments"
      assign_if_not_empty "ipv6_address" "$line" ".ipv6_address"
      assign_if_not_empty "ipv6_cidr" "$line" ".ipv6_cidr"
      assign_if_not_empty "ipv6_comments" "$line" ".ipv6_comments"
      assign_if_not_empty "ipv6_gateway" "$line" ".ipv6_gateway"
      assign_if_not_empty "ipv6_netmask" "$line" ".ipv6_netmask"
      assign_if_not_empty "bridge_ports" "$line" ".bridge_ports"

      assign_if_not_empty "bridge_vids" "$line" ".bridge_vids"
      assign_if_not_empty "bridge_vlan_aware" "$line" ".bridge_vlan_aware"
      assign_if_not_empty "bond_primary" "$line" ".bond_primary"
      assign_if_not_empty "bond_mode" "$line" ".bond_mode"
      assign_if_not_empty "bond_xmit_hash_policy" "$line" ".bond_xmit_hash_policy"
      assign_if_not_empty "ovs_bonds" "$line" ".ovs_bonds"
      assign_if_not_empty "ovs_bridge" "$line" ".ovs_bridge"
      assign_if_not_empty "ovs_options" "$line" ".ovs_options"
      assign_if_not_empty "ovs_ports" "$line" ".ovs_ports"
      assign_if_not_empty "ovs_tag" "$line" ".ovs_tag"
      assign_if_not_empty "iface_slaves" "$line" ".iface_slaves"

      # cloud init

      assign_if_not_empty "vm_ci_user" "$line" ".vm_ci_user"
      assign_if_not_empty "vm_ci_password" "$line" ".vm_ci_password"
      assign_if_not_empty "vm_ci_ssh_key" "$line" ".vm_ci_ssh_key"
      assign_if_not_empty "vm_ci_dns_ips" "$line" ".vm_ci_dns_ips"
      assign_if_not_empty "vm_ci_dns_domain" "$line" ".vm_ci_dns_domain"
      assign_if_not_empty "vm_ci_ip" "$line" ".vm_ci_ip"
      assign_if_not_empty "vm_ci_netmask" "$line" ".vm_ci_netmask"
      assign_if_not_empty "vm_ci_ip_gw" "$line" ".vm_ci_ip_gw"
      #
      assign_if_not_empty "cloudinit_image_full_path" "$line" ".cloudinit_image_full_path"
      assign_if_not_empty "dest_proxmox_storage" "$line" ".dest_proxmox_storage"

      devkit_utils.text.echo_trace.to.text.to.stderr.sh ":: GET JSON FROM STDIN - $line"
      # exit 1

      # ARG_ACTION=$(printf "%s\n" "$line" | jq -r ".action")
      PROXMOX_NODE=$(printf "%s\n" "$line" | jq -r ".proxmox_node")

      # devkit_utils.text.echo_trace.to.text.to.stderr.sh ":: EXTRA VAR"
      # devkit_utils.text.echo_trace.to.text.to.stderr.sh "${EXTRA_VAR}"

      ####
      #### DEBUG BLOCK
      ####

      if [ "$DEBUG" = true ]; then

        cat <<EOF >/tmp/debug
            (
                ANSIBLE_CONFIG="$ANSIBLE_CONFIG" \
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ansible-playbook -i "$INVENTORY" "${VAULT_ARGS[@]}" /dev/stdin <<PLAYBOOK
            - hosts: $PROXMOX_NODE
              gather_facts: false
              vars_files:
                - "$PLAYBOOK_VARS_FILE"
              tasks:
                - name: RUN $ROLE_NAME WITH VARS
                  include_role:
                    name: $ROLE_NAME
                  vars:
                    proxmox_vm_action: "$ARG_ACTION"
            $EXTRA_VAR
            PLAYBOOK
            )
EOF
        # devkit_utils.text.echo_trace.to.text.to.stderr.sh ":: cat /tmp/debug to see inline playbook "
      fi

      ####
      #### DEBUG BLOCK
      ####

      (
        ANSIBLE_CONFIG="$ANSIBLE_CONFIG" \
          ansible-playbook -i "$INVENTORY" "${VAULT_ARGS[@]}" /dev/stdin <<EOF
      - hosts: $PROXMOX_NODE
        gather_facts: false
        vars_files:
          - "$PLAYBOOK_VARS_FILE"
        tasks:
          - name: RUN $ROLE_NAME WITH VARS
            include_role:
              name: $ROLE_NAME
            vars:
              proxmox_vm_action: "$ARG_ACTION"
      ${EXTRA_VAR}
EOF
      )

      # | jq -c --arg action "$ARG_ACTION" '
      #    .plays[].tasks[]
      #   | .hosts[]
      #   | select(type=="object" and has($action))
      #   | .[$action]
      # '

    else

      devkit_utils.text.echo_trace.to.text.to.stderr.sh ":: TEXT DETECTED :: GET DATA FROM STDIN"
    fi
  done

else

  # NO STDIN DATA - USE VAULT (default) VALUE
  #
  devkit_utils.text.echo_trace.to.text.to.stderr.sh "NO STDIN VALUE"
  exit 1

fi
