#!/bin/bash

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo NAME
  echo "  $(basename "$0") - Warmup checks - check for STDIN. "
  echo
  echo SYNOPSIS
  echo "  $(basename "$0") [-h|--help] "
  echo ""

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
