#!/bin/bash

#
# quick and dirty tests
#

IFS=$'\n'

#################################################################

list_running_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_list running vm with filter        - proxmox_vm.list_running_and_extract_vm_id.to.text.sh  "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST ::ARGS:: $CURRENT_GROUP"

    proxmox_vm.list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"
}

list_running_group() {

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_list running vm without filter      - proxmox_vm.list_running_and_extract_vm_id.to.text.sh  "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    proxmox_vm.list_running_and_extract_vm_id.to.text.sh
}

#################################################################

list_stop_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_list stop vm with filter        - proxmox_vm.list_stopped.to.jsons.sh  "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST ::ARGS:: $CURRENT_GROUP"

    proxmox_vm.list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"
}

list_stop_group() {

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_list stop vm without filter      - proxmox_vm.list_stopped.to.jsons.sh  "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    proxmox_vm.list_running_and_extract_vm_id.to.text.sh
}

#################################################################

start_batch_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_batch start $CURRENT_GROUP       - proxmox_vm.vm_id.start.to.jsons.sh  "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    for vm_id in $(
        proxmox_vm.list_stopped.to.jsons.sh "$CURRENT_GROUP" |
            jq -r ".vm_id"
    ); do

        devkit_utils.text.echo_trace.to.text.to.stderr.sh "$vm_id"
        (
            echo "$vm_id" |
                proxmox_vm.vm_id.start.to.jsons.sh # --text
        )

        sleep 3
    done

}

#################################################################

pause_batch_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_batch pause $CURRENT_GROUP       - proxmox_vm.vm_id.pause.to.jsons.sh  "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    for vm_id in $(proxmox_vm.list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"); do

        devkit_utils.text.echo_trace.to.text.to.stderr.sh "$vm_id"

        (
            echo "$vm_id" |
                proxmox_vm.vm_id.pause.to.jsons.sh # --text
        )

        sleep 3
    done

}

#################################################################

resume_batch_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_batch resume $CURRENT_GROUP       - proxmox_vm.vm_id.resume.to.jsons.sh  "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    for vm_id in $(proxmox_vm.list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"); do

        devkit_utils.text.echo_trace.to.text.to.stderr.sh "$vm_id"

        (
            echo "$vm_id" |
                proxmox_vm.vm_id.resume.to.jsons.sh # --text
        )

        sleep 3
    done

}

#################################################################

stop_batch_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_batch stop_force $CURRENT_GROUP       - proxmox_vm.vm_id.stop_force.to.jsons.sh  "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    proxmox_vm.list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"

    for vm_id in $(proxmox_vm.list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"); do

        devkit_utils.text.echo_trace.to.text.to.stderr.sh "$vm_id"

        (
            echo "$vm_id" |
                proxmox_vm.vm_id.stop_force.to.jsons.sh # --text

        )

        sleep 3
    done

}

#################################################################

pause_all() {

    devkit_utils.text.echo_separator.to.text.to.stderr.sh
    CURRENT_TEST="_batch stop all vm $CURRENT_GROUP       - proxmox_vm.vm_id.stop_force.to.jsons.sh  "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    proxmox_vm.list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"

    for vm_id in $(proxmox_vm.list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"); do

        devkit_utils.text.echo_trace.to.text.to.stderr.sh "$vm_id"

        (
            echo "$vm_id" |
                proxmox_vm.vm_id.stop_force.to.jsons.sh # --text

        )

        sleep 3
    done

}

#################################################################

mass_test() {

    local CURRENT_GROUP="$1"
    devkit_utils.text.echo_separator.to.text.to.stderr.sh
    CURRENT_TEST="_mass start         $CURRENT_GROUP       - proxmox_vm.start_all_vms.to.jsons.sh "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"
    proxmox_vm.start_all_vms.to.jsons.sh "$CURRENT_GROUP"

    sleep 10 # to fast for proxmo web ui...

    devkit_utils.text.echo_separator.to.text.to.stderr.sh
    CURRENT_TEST="_mass pause         $CURRENT_GROUP       - proxmox_vm.pause_all_vms.to.jsons.sh "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"
    proxmox_vm.pause_all_vms.to.jsons.sh "$CURRENT_GROUP"

    sleep 10 # to fast for proxmo web ui...

    devkit_utils.text.echo_separator.to.text.to.stderr.sh
    CURRENT_TEST="_mass resume        $CURRENT_GROUP       - proxmox_vm.resume_all_vms.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"
    proxmox_vm.resume_all_vms.to.jsons.sh "$CURRENT_GROUP"

    sleep 10 # to fast for proxmo web ui...

    devkit_utils.text.echo_separator.to.text.to.stderr.sh
    CURRENT_TEST="_mass stop          $CURRENT_GROUP       - proxmox_vm.stop_force_all_vms.to.jsons.sh "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"
    proxmox_vm.stop_force_all_vms.to.jsons.sh "$CURRENT_GROUP"

    sleep 10 # to fast for proxmo web ui...

    #
    devkit_utils.text.echo_separator.to.text.to.stderr.sh
    CURRENT_TEST="_mass start         $CURRENT_GROUP       - proxmox_vm.start_all_vms.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"
    proxmox_vm.start_all_vms.to.jsons.sh "$CURRENT_GROUP"

    sleep 10 # to fast for proxmo web ui...
    #

    CURRENT_GROUP="no_group"

    devkit_utils.text.echo_separator.to.text.to.stderr.sh
    CURRENT_TEST="_mass pause         $CURRENT_GROUP       - proxmox_vm.pause_all_vms.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"
    proxmox_vm.pause_all_vms.to.jsons.sh

    sleep 10 # to fast for proxmo web ui...

    devkit_utils.text.echo_separator.to.text.to.stderr.sh
    CURRENT_TEST="_mass resume        $CURRENT_GROUP       - proxmox_vm.resume_all_vms.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"
    proxmox_vm.resume_all_vms.to.jsons.sh

    sleep 10 # to fast for proxmo web ui...

    devkit_utils.text.echo_separator.to.text.to.stderr.sh
    CURRENT_TEST="_mass stop_force    $CURRENT_GROUP       - proxmox_vm.stop_force_all_vms.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"
    proxmox_vm.stop_force_all_vms.to.jsons.sh

}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# list_running_group_with_filter "group-01"
# list_running_group_with_filter "group-02"
# list_running_group_with_filter "group-03"

# #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# list_running_group

# #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# list_stop_group_with_filter "group-01"
# list_stop_group_with_filter "group-02"
# list_stop_group_with_filter "group-03"

# #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# list_stop_group

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# start_batch_group_with_filter "group-01"
# pause_batch_group_with_filter "group-01"
# resume_batch_group_with_filter "group-01"
# stop_batch_group_with_filter "group-01"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

mass_test "group-01"
mass_test "group-02"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
