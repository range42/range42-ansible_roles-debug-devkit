#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

showExample() {
  echo ""
  echo "  $(basename "$0") KEY_FIELD value_to_grep "
  echo "  echo '{\"key1\": \"value1\", \"key2\": \"value2\", \"key3\": \"value3\"}' | $(basename "$0") key1 value1"
  echo
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo NAME
  echo "  $(basename "$0") - select on key field with specified value"
  echo
  echo SYNOPSIS
  echo "  $(basename "$0") [-h|--help] key1[,key2,...]"
  echo
  echo DESCRIPTION
  echo "   Accept JSON data from STDIN and grep the specified key field."
  echo
  echo EXAMPLES
  showExample
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# WARMUP CHECKS
#

devkit_ansible.proxmox_controller._inc.warmup_checks_stdin.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# #
# # STDIN check
# #

# if [ -t 0 ]; then
#   echo ":: error : no STDIN data" 1>&2
#   exit 1
# fi

# check arguments
if [ $# -ne 2 ]; then
  devkit_generic.utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
  showExample
  exit 1
fi

KEY_FIELD_ARG="$1"
KEY_FILTER_ARG="$2"

jq -c \
  --arg jq_KEY_FIELD_ARG "$KEY_FIELD_ARG" \
  --arg jq_KEY_FILTER_ARG "$KEY_FILTER_ARG" \
  'select(
   .[$jq_KEY_FIELD_ARG]==$jq_KEY_FILTER_ARG
  )'
