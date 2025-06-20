#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

show_example() {

  echo "  $(basename "$0") KEY_FIELD value_to_grep "
  echo "  echo '{\"key1\": \"value1\", \"key2\": \"value2\", \"key3\": \"value3\"}' | $(basename "$0") key1 value1"

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo "  $(basename "$0") - select on key field with specified value"
  echo
  echo OPTIONS
  echo
  echo "                     $(basename "$0") [-h|--help]"
  echo "  STDIN :: [jsons] | $(basename "$0") key1 value1"
  echo
  echo DESCRIPTION
  echo
  echo "   Accept JSON data from STDIN and grep the specified key field."
  echo
  echo EXAMPLES
  echo
  show_example
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# WARMUP CHECKS
#

proxmox__inc.warmup_checks_stdin.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

# #
# # STDIN check
# #

# check arguments
if [ $# -ne 2 ]; then
  devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
  show_example
  exit 1

else
  KEY_FIELD_ARG="$1"
  KEY_FILTER_ARG="$2"

  jq -c \
    --arg jq_KEY_FIELD_ARG "$KEY_FIELD_ARG" \
    --argjson jq_KEY_FILTER_ARG "$KEY_FILTER_ARG" \
    '
      select(
        .[$jq_KEY_FIELD_ARG] == $jq_KEY_FILTER_ARG
      )
    '

fi
