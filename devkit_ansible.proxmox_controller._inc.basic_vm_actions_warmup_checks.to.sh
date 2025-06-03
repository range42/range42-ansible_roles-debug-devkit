#!/bin/bash

#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

ARG_ACTION="${1:-}"
ALLOWED_ACTIONS=(
  vm_delete
  vm_pause
  vm_resume
  vm_start
  vm_stop
  vm_stop_force
  vm_list
)

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo NAME
  echo "  $(basename "$0") - Warmup checks - check for vm_actions_*"
  echo
  echo SYNOPSIS
  echo "  $(basename "$0") [-h|--help] "
  echo ""
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ -z "$ARG_ACTION" ]]; then
  devkit_generic.utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
  # showExample
  exit 1
fi

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

  devkit_generic.utils.text.echo_error.to.text.to.stderr.sh "Invalid action - '$ARG_ACTION'"

  for action in "${ALLOWED_ACTIONS[@]}"; do
    devkit_generic.utils.text.echo_error.to.text.to.stderr.sh " - allowed - '$action'"
  done
  exit 1
fi
