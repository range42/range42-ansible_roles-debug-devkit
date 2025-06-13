#!/bin/bash

ansible-inventory -i "$RANGE42_ANSIBLE_ROLES__INVENTORY_DIR/off_cr_42.yaml" --graph
