#!/bin/bash

#
# quick and dirty tests
#

IFS=$'\n'

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

lxc_start() {

    local CURRENT_GROUP="$1"

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_list running vm with filter        - proxmox_lxc.vm_id.start.to.jsons.sh"
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    proxmox_lxc.list.to.jsons.sh "$CURRENT_GROUP" |
        proxmox_lxc.vm_id.start.to.jsons.sh
}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

lxc_stop() {

    local CURRENT_GROUP="$1"

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_list running vm with filter        -  proxmox_lxc.vm_id.stop.to.jsons.sh  "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    proxmox_lxc.list.to.jsons.sh "$CURRENT_GROUP" |
        proxmox_lxc.vm_id.stop.to.jsons.sh
}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

lxc_stop_force() {

    local CURRENT_GROUP="$1"

    devkit_utils.text.echo_separator.to.text.to.stderr.sh

    CURRENT_TEST="_list running vm with filter        -  proxmox_lxc.vm_id.stop_force.to.jsons.sh  "
    devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_TEST"

    proxmox_lxc.list.to.jsons.sh "$CURRENT_GROUP" |
        proxmox_lxc.vm_id.stop_force.to.jsons.sh
}

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

lxc_start "test-"
lxc_stop "test-"

lxc_start "test-"
lxc_stop_force "test-"
