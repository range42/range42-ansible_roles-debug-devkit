#!/bin/bash

#
# quick and dirty tests
#

IFS=$'\n'

#################################################################

download_cloud_init_files() {

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="downloading cloud init files  - proxmox_storage.urls.download_iso.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST ::"

    echo '{"proxmox_storage":"local","iso_file_content_type":"iso", "iso_url":"https://cloud-images.ubuntu.com/minimal/daily/noble/current/noble-minimal-cloudimg-amd64.img", "iso_file_name": "noble-minimal-cloudimg-amd64.img"}' | proxmox_storage.urls.download_iso.to.jsons.sh
    echo '{"proxmox_storage":"local","iso_file_content_type":"iso", "iso_url":"https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img", "iso_file_name": "noble-server-cloudimg-amd64.img"}' | proxmox_storage.urls.download_iso.to.jsons.sh
    echo '{"proxmox_storage":"local","iso_file_content_type":"iso", "iso_url":"https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.raw", "iso_file_name": "debian-12-genericcloud-amd64.img"}' | proxmox_storage.urls.download_iso.to.jsons.sh

    echo ""
    echo ""
    echo ""

}

create_vm_templates() {

    VM_ID="$1"     # 99xx
    VM_NAME="$2"   # "template-vm-nano"
    VM_CORE="$3"   # "1"
    VM_MEMORY="$4" # "1024"
    VM_DISK="$5"   # "32g"
    VM_IP="$6"     # "192.168.42.217"

    printf '{"proxmox_node":"px-testing","vm_id":%s,"vm_name":"%s","vm_cpu":"host","vm_cores":%s,"vm_sockets":1,"vm_memory":%s} \n' "$VM_ID" "$VM_NAME" "$VM_CORE" "$VM_MEMORY" |
        proxmox_vm.jsons.create.to.jsons.sh

    printf '{"vm_id":%s,"proxmox_node":"px-testing"}' "$VM_ID" |
        proxmox_template.vm_id.convert_to_template.to.jsons.sh

    printf '{"proxmox_node":"px-testing-cli","cloudinit_image_full_path":"/var/lib/vz/template/iso/noble-minimal-cloudimg-amd64.img","vm_id":%s,"vm_disk_size":"%s","dest_proxmox_storage":"local-lvm"}' "$VM_ID" "$VM_DISK" |
        proxmox_storage.vm_id.import_cloudinit_image_to_vm.to.jsons.sh

    printf '{"vm_id":%s,"proxmox_node":"px-testing","vm_ci_user":"alice","vm_ci_password":"supersecret","vm_ci_ssh_key":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOe+sCgt... USER@HOST","vm_ci_namerserver_ips":"1.1.1.1","vm_ci_ip":"%s","vm_ci_netmask":"24","vm_ci_ip_gw":"192.168.42.1"}' "$VM_ID" "$VM_IP" |
        proxmox_template.vm_id.set_cloudinit_variables.to.jsons.sh

    printf '{"vm_id":%s,"vm_tag_name":"templates"}' "$VM_ID" | proxmox_vm.jsons.set_tag.to.jsons.sh

}

create_admin_vm() {

    NEW_VM_ID="112"
    NEW_VM_NAME="admin-wazuh"
    VM_IP="192.168.42.55"

    printf '{"vm_id":9901,"vm_new_id":%s,"vm_name":"%s","vm_description":"my description"}' "$NEW_VM_ID" "$NEW_VM_NAME" | proxmox_vm.jsons.clone.to.jsons.sh
    printf '{"vm_id":%s,"vm_tag_name":"admin"}' "$NEW_VM_ID" | proxmox_vm.jsons.set_tag.to.jsons.sh
    printf '{"vm_id":%s,"proxmox_node":"px-testing","vm_ci_user":"bob","vm_ci_password":"supersecret","vm_ci_ssh_key":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOe+sCgt... USER@HOST","vm_ci_namerserver_ips":"1.1.1.1","vm_ci_ip":"%s","vm_ci_netmask":"24","vm_ci_ip_gw":"192.168.42.1"}' "$NEW_VM_ID" "$VM_IP" |
        proxmox_template.vm_id.set_cloudinit_variables.to.jsons.sh
    printf '{"vm_id":%s,"proxmox_node":"px-testing" }' $NEW_VM_ID | proxmox_vm.vm_id.start.to.jsons.sh

    ####

    NEW_VM_ID="113"
    NEW_VM_NAME="admin-kong"
    VM_IP="192.168.42.56"

    printf '{"vm_id":9901,"vm_new_id":%s,"vm_name":"%s","vm_description":"my description"}' "$NEW_VM_ID" "$NEW_VM_NAME" | proxmox_vm.jsons.clone.to.jsons.sh
    printf '{"vm_id":%s,"vm_tag_name":"admin"}' "$NEW_VM_ID" | proxmox_vm.jsons.set_tag.to.jsons.sh
    printf '{"vm_id":%s,"proxmox_node":"px-testing","vm_ci_user":"bob","vm_ci_password":"supersecret","vm_ci_ssh_key":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOe+sCgt... USER@HOST","vm_ci_namerserver_ips":"1.1.1.1","vm_ci_ip":"%s","vm_ci_netmask":"24","vm_ci_ip_gw":"192.168.42.1"}' "$NEW_VM_ID" "$VM_IP" |
        proxmox_template.vm_id.set_cloudinit_variables.to.jsons.sh
    printf '{"vm_id":%s,"proxmox_node":"px-testing" }' $NEW_VM_ID | proxmox_vm.vm_id.start.to.jsons.sh

    ####

    NEW_VM_ID="114"
    NEW_VM_NAME="admin-deployer"
    VM_IP="192.168.42.57"

    printf '{"vm_id":9901,"vm_new_id":%s,"vm_name":"%s","vm_description":"my description"}' "$NEW_VM_ID" "$NEW_VM_NAME" | proxmox_vm.jsons.clone.to.jsons.sh
    printf '{"vm_id":%s,"vm_tag_name":"admin"}' "$NEW_VM_ID" | proxmox_vm.jsons.set_tag.to.jsons.sh
    printf '{"vm_id":%s,"proxmox_node":"px-testing","vm_ci_user":"bob","vm_ci_password":"supersecret","vm_ci_ssh_key":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOe+sCgt... USER@HOST","vm_ci_namerserver_ips":"1.1.1.1","vm_ci_ip":"%s","vm_ci_netmask":"24","vm_ci_ip_gw":"192.168.42.1"}' "$NEW_VM_ID" "$VM_IP" |
        proxmox_template.vm_id.set_cloudinit_variables.to.jsons.sh
    printf '{"vm_id":%s,"proxmox_node":"px-testing" }' $NEW_VM_ID | proxmox_vm.vm_id.start.to.jsons.sh

}

####

# download_cloud_init_files

####

# list current templates
# proxmox_vm.list.to.jsons.sh template-vm
# delete current templates
# proxmox_vm.list.to.jsons.sh template-vm | proxmox_vm.vm_id.delete.to.jsons.sh

#####

# create_vm_templates "9901" "template-vm-nano" "1" "1024" "34g" "192.168.42.217"
# devkit_utils.text.echo_separator.to.text.to.stderr.sh
# #

# create_vm_templates "9911" "template-vm-micro-01-2g-24g" "1" "2042" "24g" "192.168.42.111"
# create_vm_templates "9912" "template-vm-micro-02-2g-24g" "2" "2042" "24g" "192.168.42.112"
# devkit_utils.text.echo_separator.to.text.to.stderr.sh
# #
# create_vm_templates "9921" "template-vm-small-01-4g-32g" "1" "4096" "32g" "192.168.42.121"
# create_vm_templates "9922" "template-vm-small-02-4g-32g" "2" "4096" "32g" "192.168.42.122"
# create_vm_templates "9924" "template-vm-small-04-4g-32g" "4" "4096" "32g" "192.168.42.124"
# devkit_utils.text.echo_separator.to.text.to.stderr.sh
# #
# create_vm_templates "9934" "template-vm-medium-02-8g-64g" "2" "8192" "64g" "192.168.42.132"
# create_vm_templates "9934" "template-vm-medium-04-8g-64g" "4" "8192" "64g" "192.168.42.134"
# create_vm_templates "9936" "template-vm-medium-06-8g-64g" "6" "8192" "64g" "192.168.42.136"
# devkit_utils.text.echo_separator.to.text.to.stderr.sh
# #
# create_vm_templates "9944" "template-vm-large-04-16g-100g" "4" "16384" "100g" "192.168.42.144"
# create_vm_templates "9946" "template-vm-large-06-16g-100g" "6" "16384" "100g" "192.168.42.146"
# create_vm_templates "9948" "template-vm-large-08-16g-100g" "8" "16384" "100g" "192.168.42.148"
# devkit_utils.text.echo_separator.to.text.to.stderr.sh

create_admin_vm
