#!/bin/bash

#
# quick and dirty tests
#

IFS=$'\n'

#################################################################

list_running_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_generic.utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_list running vm with filter        - devkit_ansible.proxmox_controller.ask_vm_list_running_and_extract_vm_id.to.text.sh  "
    devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST ::ARGS:: $CURRENT_GROUP"

    devkit_ansible.proxmox_controller.ask_vm_list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"
}

list_running_group() {

    devkit_generic.utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_list running vm without filter      - devkit_ansible.proxmox_controller.ask_vm_list_running_and_extract_vm_id.to.text.sh  "
    devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    devkit_ansible.proxmox_controller.ask_vm_list_running_and_extract_vm_id.to.text.sh
}

#################################################################

list_stop_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_generic.utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_list stop vm with filter        - devkit_ansible.proxmox_controller.ask_vm_list_stopped.to.jsons.sh  "
    devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST ::ARGS:: $CURRENT_GROUP"

    devkit_ansible.proxmox_controller.ask_vm_list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"
}

list_stop_group() {

    devkit_generic.utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_list stop vm without filter      - devkit_ansible.proxmox_controller.ask_vm_list_stopped.to.jsons.sh  "
    devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    devkit_ansible.proxmox_controller.ask_vm_list_running_and_extract_vm_id.to.text.sh
}

#################################################################

start_batch_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_generic.utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_batch start $CURRENT_GROUP       - devkit_ansible.proxmox_controller.vm_id.ask_vm_start.to.jsons.sh  "
    devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    for vm_id in $(
        devkit_ansible.proxmox_controller.ask_vm_list_stopped.to.jsons.sh "$CURRENT_GROUP" |
            jq -r ".vm_id"
    ); do

        devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$vm_id"
        (
            echo "$vm_id" |
                devkit_ansible.proxmox_controller.vm_id.ask_vm_start.to.jsons.sh # --text
        )

        sleep 3
    done

}

#################################################################

pause_batch_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_generic.utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_batch pause $CURRENT_GROUP       - devkit_ansible.proxmox_controller.vm_id.ask_vm_pause.to.jsons.sh  "
    devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    for vm_id in $(devkit_ansible.proxmox_controller.ask_vm_list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"); do

        devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$vm_id"

        (
            echo "$vm_id" |
                devkit_ansible.proxmox_controller.vm_id.ask_vm_pause.to.jsons.sh # --text
        )

        sleep 3
    done

}

#################################################################

resume_batch_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_generic.utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_batch resume $CURRENT_GROUP       - devkit_ansible.proxmox_controller.vm_id.ask_vm_resume.to.jsons.sh  "
    devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    for vm_id in $(devkit_ansible.proxmox_controller.ask_vm_list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"); do

        devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$vm_id"

        (
            echo "$vm_id" |
                devkit_ansible.proxmox_controller.vm_id.ask_vm_resume.to.jsons.sh # --text
        )

        sleep 3
    done

}

#################################################################

stop_batch_group_with_filter() {

    local CURRENT_GROUP="$1"

    devkit_generic.utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_batch stop_force $CURRENT_GROUP       - devkit_ansible.proxmox_controller.vm_id.ask_vm_stop_force.to.jsons.sh  "
    devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    devkit_ansible.proxmox_controller.ask_vm_list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"

    for vm_id in $(devkit_ansible.proxmox_controller.ask_vm_list_running_and_extract_vm_id.to.text.sh "$CURRENT_GROUP"); do

        devkit_generic.utils.text.echo_trace.to.text.to.stderr.sh "$vm_id"

        (
            echo "$vm_id" |
                devkit_ansible.proxmox_controller.vm_id.ask_vm_stop_force.to.jsons.sh # --text

        )

        sleep 3
    done

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

start_batch_group_with_filter "group-01"
pause_batch_group_with_filter "group-01"
resume_batch_group_with_filter "group-01"
stop_batch_group_with_filter "group-01"

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
