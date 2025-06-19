#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

show_example() {
  echo "  $(basename "$0") key1,key2"
  echo "  echo '{\"key1\": \"value1\", \"key2\": \"value2\", \"key3\": \"value3\"}' | $(basename "$0") \"key1,key2\""
  echo "  echo '{\"key1\": \"value1\", \"key2\": \"value2\", \"key3\": \"value3\"}' | $(basename "$0") key1"
}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo "  $(basename "$0") - Remove specified keys from JSON data"
  echo
  echo OPTIONS
  echo "                     $(basename "$0") [-h|--help] key1[,key2,...]"
  echo "  STDIN :: [jsons] | $(basename "$0") key1"
  echo
  echo DESCRIPTION
  echo "  Accept JSON data from STDIN and removes the specified keys."
  echo "  Note: multiple keys should be separated by commas with or without spaces."
  echo
  echo EXAMPLES
  echo
  show_example
  echo
  echo
  exit 1
fi

# check arguments
if [ $# -ne 1 ]; then
  devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
  show_example
  exit 1
fi

# check require jq
if ! command -v jq >/dev/null 2>&1; then
  echo ":: error: jq is not installed" >&2
  exit 2
fi

# parse key, remove space and commas
keys_input="$(echo "$1" | tr -d '[:space:]')"
IFS=',' read -r -a keys <<<"$keys_input"

# build jq delete expression
del_expr='.'
for key in "${keys[@]}"; do

  safe_key=$(
    printf '%s' "$key" |
      sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
  )

  del_expr+=" | del(.\"${safe_key}\")"

done

#### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

(
  cat - |
    tee >(jq -e . >/dev/null) |
    jq -c "${del_expr}"
)
