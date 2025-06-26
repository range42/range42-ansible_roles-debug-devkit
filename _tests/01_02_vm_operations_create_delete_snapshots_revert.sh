#!/bin/bash

#
# quick and dirty tests
#

IFS=$'\n'

#################################################################

vm_create() {

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_vm_create tests - proxmox_vm.jsons.create.to.jsons.sh "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST ::"
    # devkit_utils.text.echo_separator.to.text.to.stderr.sh

    echo '{"proxmox_node":"px-testing","vm_id":42421,"vm_name":"test-vm-01","vm_cpu":"host","vm_cores":1,"vm_sockets":1,"vm_memory":1024,"vm_disk_size":42,"vm_iso_file":"local:iso/ubuntu-24.04.2-live-server-amd64.iso"}' | proxmox_vm.jsons.create.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42422,"vm_name":"test-vm-02","vm_cpu":"host","vm_cores":1,"vm_sockets":1,"vm_memory":1024,"vm_disk_size":42,"vm_iso_file":"local:iso/ubuntu-24.04.2-live-server-amd64.iso"}' | proxmox_vm.jsons.create.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42423,"vm_name":"test-vm-03","vm_cpu":"host","vm_cores":1,"vm_sockets":1,"vm_memory":1024,"vm_disk_size":42,"vm_iso_file":"local:iso/ubuntu-24.04.2-live-server-amd64.iso"}' | proxmox_vm.jsons.create.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42424,"vm_name":"test-vm-04","vm_cpu":"host","vm_cores":1,"vm_sockets":1,"vm_memory":1024,"vm_disk_size":42,"vm_iso_file":"local:iso/ubuntu-24.04.2-live-server-amd64.iso"}' | proxmox_vm.jsons.create.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42425,"vm_name":"test-vm-05","vm_cpu":"host","vm_cores":1,"vm_sockets":1,"vm_memory":1024,"vm_disk_size":42,"vm_iso_file":"local:iso/ubuntu-24.04.2-live-server-amd64.iso"}' | proxmox_vm.jsons.create.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42426,"vm_name":"test-vm-06","vm_cpu":"host","vm_cores":1,"vm_sockets":1,"vm_memory":1024,"vm_disk_size":42,"vm_iso_file":"local:iso/ubuntu-24.04.2-live-server-amd64.iso"}' | proxmox_vm.jsons.create.to.jsons.sh

    echo
    echo
    echo

    proxmox_vm.list.to.jsons.sh "test-vm" | proxmox_vm.vm_id.stop_force.to.jsons.sh

}

#################################################################

vm_list() {

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_vm_create tests - proxmox_vm.vm_id.list_vm_and_extract_vm_name.to.jsons.sh "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST ::"

    proxmox_vm.list.to.jsons.sh
    # proxmox_vm.list.to.jsons.sh | jq -c ".vm_id" | proxmox_vm.vm_id.list_vm_and_extract_vm_name.to.jsons.sh

    proxmox_vm.list.to.jsons.sh "test-vm"

    echo
    echo
    echo
}

#################################################################

vm_snapshots() {

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_vm_create_snapshot tests - proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST :: "

    echo 9000 | proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh

    echo '{"vm_id":42421}' | proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42421}' | proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42421,"vm_snapshot_name":"REVERT_TEST"}' | proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42421,"vm_snapshot_description":"MY_DESCRIPTION"}' | proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42421,"vm_snapshot_name":"MY_vm_SNAPSHOT_01","vm_snapshot_description":"MY_DESCRIPTION"}' | proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh
    echo '{"vm_id":42421}' | proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42421,"vm_snapshot_name":"WILL_BE_DELETED","vm_snapshot_description":"MY_DESCRIPTION"}' | proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh
    echo '{"vm_id":42421}' | proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh
    echo '{"vm_id":42421}' | proxmox_snapshot_vm.vm_id.create_snapshot.to.jsons.sh

    # snapshots delete

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_vm_delete_snapshot tests -  proxmox_snapshot_vm.vm_id.delete_snapshot.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST :: "

    echo '{"proxmox_node":"px-testing","vm_id":42421,"vm_snapshot_name":"MY_vm_SNAPSHOT_01"}' | proxmox_snapshot_vm.vm_id.delete_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42421,"vm_snapshot_name":"WILL_BE_DELETED"}' | proxmox_snapshot_vm.vm_id.delete_snapshot.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42421}'
    echo '{"vm_id":42421}'
    echo '{"vm_id":42421}'

    # snapshots revert

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_vm_revert_snapshot tests -  proxmox_snapshot_vm.vm_id.revert_snapshot.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST :: "

    echo '{"proxmox_node":"px-testing","vm_id":42421,"vm_snapshot_name":"REVERT_TEST"}' | proxmox_snapshot_vm.vm_id.revert_snapshot.to.jsons.sh

}

#################################################################

vm_delete() { # done

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_vm_delete tests - proxmox_vm.vm_id.delete.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST :: "

    echo 4242 | proxmox_vm.vm_id.delete.to.jsons.sh

    echo '{"proxmox_node":"px-testing","vm_id":42421}' | proxmox_vm.vm_id.delete.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42422}' | proxmox_vm.vm_id.delete.to.jsons.sh
    echo '{"proxmox_node":"px-testing","vm_id":42423}' | proxmox_vm.vm_id.delete.to.jsons.sh

    proxmox_vm.list.to.jsons.sh "test-vm-" | jq -c ".vm_id" | proxmox_vm.vm_id.delete.to.jsons.sh

}

#################################################################

vm_create
vm_list

vm_snapshots

# should add stop func.

vm_delete
