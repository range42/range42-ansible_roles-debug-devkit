#!/bin/bash

#
# quick and dirty tests
#

IFS=$'\n'

#################################################################

lxc_create() {

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_lxc_create tests - proxmox_lxc.jsons.create.to.jsons.sh "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST ::"
    # devkit_utils.text.echo_separator.to.text.to.stderr.sh

    echo '{"vm_id":"9000","lxc_name":"test-lxc-00","lxc_template":"local:vztmpl/alpine-3.19-default_20240207_amd64.tar.xz","lxc_password":"testtest","lxc_ssh_pubkeys":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOe+sCgtn+aMe+9S1ACsv8tJ2uupHNqsbwIgBpeaIA7s","lxc_cpu":"1","lxc_cores":"1","lxc_memory":"2048","proxmox_storage":"local-lvm","lxc_disk_size":"16","lxc_net_name":"eth0","lxc_bridge":"vmbr0","lxc_ip":"192.168.42.231/24","lxc_gateway":"192.168.42.1","lxc_dns_primary":"1.1.1.1","lxc_dns_secondary":"4.2.2.4"}' | proxmox_lxc.jsons.create.to.jsons.sh
    echo '{"vm_id":"9001","lxc_name":"test-lxc-01","lxc_template":"local:vztmpl/alpine-3.19-default_20240207_amd64.tar.xz","lxc_password":"testtest","lxc_ssh_pubkeys":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOe+sCgtn+aMe+9S1ACsv8tJ2uupHNqsbwIgBpeaIA7s","lxc_cpu":"1","lxc_cores":"1","lxc_memory":"2048","proxmox_storage":"local-lvm","lxc_disk_size":"16","lxc_net_name":"eth0","lxc_bridge":"vmbr0","lxc_ip":"192.168.42.232/24","lxc_gateway":"192.168.42.1","lxc_dns_primary":"1.1.1.1","lxc_dns_secondary":"4.2.2.4"}' | proxmox_lxc.jsons.create.to.jsons.sh
    echo '{"vm_id":"9002","lxc_name":"test-lxc-02","lxc_template":"local:vztmpl/alpine-3.19-default_20240207_amd64.tar.xz","lxc_password":"testtest","lxc_ssh_pubkeys":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOe+sCgtn+aMe+9S1ACsv8tJ2uupHNqsbwIgBpeaIA7s","lxc_cpu":"1","lxc_cores":"1","lxc_memory":"2048","proxmox_storage":"local-lvm","lxc_disk_size":"16","lxc_net_name":"eth0","lxc_bridge":"vmbr0","lxc_ip":"192.168.42.233/24","lxc_gateway":"192.168.42.1","lxc_dns_primary":"1.1.1.1","lxc_dns_secondary":"4.2.2.4"}' | proxmox_lxc.jsons.create.to.jsons.sh

    echo
    echo
    echo
}

#################################################################

lxc_list() {

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_lxc_create tests - proxmox_lxc.vm_id.list_lxc_and_extract_vm_name.to.jsons.sh "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST ::"

    proxmox_lxc.list.to.jsons.sh
    proxmox_lxc.list.to.jsons.sh | jq -c ".vm_id" | proxmox_lxc.vm_id.list_lxc_and_extract_vm_name.to.jsons.sh

    echo
    echo
    echo
}

#################################################################

lxc_snapshots() {

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_lxc_create_snapshot tests - proxmox_snapshot_lxc.vm_id.create_snapshot.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST :: "

    echo 9000 | proxmox_snapshot_lxc.vm_id.create_snapshot.to.jsons.sh

    echo '{"vm_id":9000}' | proxmox_snapshot_lxc.vm_id.create_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":9000}' | proxmox_snapshot_lxc.vm_id.create_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":9000,"lxc_snapshot_name":"REVERT_TEST"}' | proxmox_snapshot_lxc.vm_id.create_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":9000,"lxc_snapshot_description":"MY_DESCRIPTION"}' | proxmox_snapshot_lxc.vm_id.create_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":9000,"lxc_snapshot_name":"MY_LXC_SNAPSHOT_01","lxc_snapshot_description":"MY_DESCRIPTION"}' | proxmox_snapshot_lxc.vm_id.create_snapshot.to.jsons.sh
    echo '{"vm_id":9000}' | proxmox_snapshot_lxc.vm_id.create_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":9000,"lxc_snapshot_name":"WILL_BE_DELETED","lxc_snapshot_description":"MY_DESCRIPTION"}' | proxmox_snapshot_lxc.vm_id.create_snapshot.to.jsons.sh
    echo '{"vm_id":9000}' | proxmox_snapshot_lxc.vm_id.create_snapshot.to.jsons.sh
    echo '{"vm_id":9000}' | proxmox_snapshot_lxc.vm_id.create_snapshot.to.jsons.sh

    # snapshots delete

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_lxc_delete_snapshot tests -  proxmox_snapshot_lxc.vm_id.delete_snapshot.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST :: "

    echo '{"proxmox_node":"px-testing","vm_id":9000,"lxc_snapshot_name":"MY_LXC_SNAPSHOT_01"}' | proxmox_snapshot_lxc.vm_id.delete_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":9000,"lxc_snapshot_name":"WILL_BE_DELETED"}' | proxmox_snapshot_lxc.vm_id.delete_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":9000}'
    echo '{"vm_id":9000}'
    echo '{"vm_id":9000}'

    # snapshots revert

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_lxc_revert_snapshot tests -  proxmox_snapshot_lxc.vm_id.revert_snapshot.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST :: "

    echo '{"proxmox_node":"px-testing","vm_id":9000,"lxc_snapshot_name":"REVERT_TEST"}' | proxmox_snapshot_lxc.vm_id.revert_snapshot.to.jsons.sh

}

#################################################################

lxc_delete() {

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_lxc_delete tests - proxmox_lxc.vm_id.delete.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST :: "

    echo 9000 | proxmox_lxc.vm_id.delete.to.jsons.sh

    echo '{"proxmox_node":"px-testing","vm_id":9000}' | proxmox_lxc.vm_id.delete.to.jsons.sh

    proxmox_lxc.list.to.jsons.sh "test-lxc-" | jq -c ".vm_id" | proxmox_lxc.vm_id.delete.to.jsons.sh

}

lxc_create
lxc_list
lxc_snapshots

# should add stop func.

lxc_delete
