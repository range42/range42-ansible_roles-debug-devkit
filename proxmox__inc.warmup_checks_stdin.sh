#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
# PR-26
set -euo pipefail

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then

  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Warmup checks - check for STDIN. "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "

  echo
  echo

  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# check for STDIN data.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [ -t 0 ]; then

  devkit_utils.text.echo_error.to.text.to.stderr.sh "NO STDIN DATA"
  exit 1
fi
