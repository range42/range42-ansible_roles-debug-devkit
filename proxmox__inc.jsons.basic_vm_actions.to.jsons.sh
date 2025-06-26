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
DEFAULT_OPEN_VAULT_PW_FILE_PATH="/tmp/vault/vault_pass.txt"
# CURRENT_ANSIBLE_CONFIG="./ansible_no_skipped_json.cfg"
CURRENT_ANSIBLE_CONFIG="$RANGE42_ANSIBLE_ROLES__DEVKITS_DIR/ansible_no_skipped_json.cfg"

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
INVENTORY="$RANGE42_ANSIBLE_ROLES__INVENTORY_DIR/off_cr_42.yaml"
VAULT_ARGS=("${ANSIBLE_VAULT_ARG[@]}")

PLAYBOOK_VARS_FILE="$RANGE42_ANSIBLE_ROLES__DEVKITS_DIR/secrets/px-testing.cr42_tailscale.yaml"

IFS=$'\n'

# IS STDIN ?
if [ ! -t 0 ]; then

  # devkit_utils.text.echo_trace.to.text.to.stderr.sh "IT IS STDIN "

  STDIN_DATA=$(cat -)

  IFS=$'\n'

  for line in $STDIN_DATA; do

    if printf "%s\n" "$line" | jq -e 'type == "object"' >/dev/null 2>&1; then

      # devkit_utils.text.echo_trace.to.text.to.stderr.sh ":: JSON_LINE DETECTED :: GET DATA FROM STDIN "

      assign_if_not_empty "vm_id" "$line" ".vm_id"
      assign_if_not_empty "proxmox_node" "$line" ".proxmox_node"
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

      #####################

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
      assign_if_not_empty "file_content_type" "$line" ".file_content_type"
      assign_if_not_empty "file_name" "$line" ".file_name"
      assign_if_not_empty "url" "$line" ".url"

      # bonus // extra
      assign_if_not_empty "proxmox_cluster_color_mapping" "$line" ".proxmox_cluster_color_mapping"
      assign_if_not_empty "vm_tag_name" "$line" ".vm_tag_name"
      assign_if_not_empty "lxc_tag_name" "$line" ".lxc_tag_name"

      # devkit_utils.text.echo_trace.to.text.to.stderr.sh ":: JSON_LINE DETECTED :: GET DATA FROM STDIN  - $line"
      # exir 1

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
        devkit_utils.text.echo_trace.to.text.to.stderr.sh ":: cat /tmp/debug to see inline playbook "
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
      ) | jq -c --arg action "$ARG_ACTION" '
         .plays[].tasks[]
        | .hosts[]
        | select(type=="object" and has($action))
        | .[$action]
      '

    else

      devkit_utils.text.echo_error.to.text.to.stderr.sh ":: TEXT DETECTED :: GET DATA FROM STDIN"
    fi
  done

else

  # NO STDIN DATA - USE VAULT (default) VALUE
  #
  devkit_utils.text.echo_error.to.text.to.stderr.sh "NO STDIN VALUE"
  exit 1

fi
