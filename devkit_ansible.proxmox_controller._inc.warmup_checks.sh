#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo NAME
  echo "  $(basename "$0") - Warmup checks - do not edit. "
  echo
  echo SYNOPSIS
  echo "  $(basename "$0") [-h|--help] "
  echo ""

  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# check if role can be found in ANSIBLE_ROLES_PATH
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ -z "${ANSIBLE_ROLES_PATH:-}" ]]; then

  devkit_generic.utils.text.echo_error.to.text.to.stderr.sh " ENV_ERROR :: ANSIBLE_ROLES_PATH not defined"
  exit 1
fi
