#!/bin/bash

#
# PR-57
#

set -euo pipefail
IFS=$'\n\t'

show_example() {
  # echo "  $(basename "$0") key1,key2"
  # echo "  echo '{\"key1\": \"value1\", \"key2\": \"value2\", \"key3\": \"value3\"}' | $(basename "$0")  'aaaa:bbb,ccc:ddd' "
  echo "  echo '{\"key1\": \"value1\", \"key2\": \"value2\", \"key3\": \"value3\"}' | $(basename "$0") '{\"aa\":\"bb\", \"cc\":\"dd\"}'"
  echo "  echo '{\"key1\": \"value1\", \"key2\": \"value2\", \"key3\": \"value3\"}' | $(basename "$0") '{\"test\":42}'"

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo "  $(basename "$0") - Append keys values specified in arg from STDIN JSON data"
  echo
  echo OPTIONS
  echo "                     $(basename "$0") [-h|--help] key1[,key2,...]"
  echo "  STDIN :: [jsons] | $(basename "$0") key1"
  echo
  echo DESCRIPTION
  echo "  Accept JSON line data from STDIN."
  echo "  Note: multiple keys should be separated by commas with or without spaces."
  echo
  echo EXAMPLES
  echo
  show_example
  echo
  echo
  exit 1
fi

if [ $# -eq 0 ]; then
  cat
  exit 0
fi

INPUT_JSON_LINES=$(cat -)
MERGED_JSON_LINE='{}'

for arg in "$@"; do

  # JSON as argument ? check 1
  if [[ $arg =~ ^[[:space:]]*\{.*\}[[:space:]]*$ ]]; then

    # JSON as argument ? check 2
    if echo "$arg" | jq -e 'type=="object"' >/dev/null 2>&1; then
      # $arg is probably  JSON object.

      JSON_OBJ_FROM_ARG=$(echo "$arg" | jq -c .)

      MERGED_JSON_LINE=$(
        jq -n \
          --argjson a "$MERGED_JSON_LINE" \
          --argjson b "$JSON_OBJ_FROM_ARG" \
          '$a + $b'
      )

    fi

  fi

  #
  # SUBJECT TO (easy) INJECTION => removed.
  #

  # else

  #   # probably simple text key/value
  #   IFS=, read -ra kv_pairs <<<"$arg"

  #   # build json line.
  #   first=true
  #   for kv in "${kv_pairs[@]}"; do

  #     IFS=: read -r key val <<<"$kv"

  #     if [ "$first" = true ]; then
  #       first=false
  #     else
  #       TEXT_KV_FROM_ARG+=","
  #     fi
  #     # ACCEPT ONLY STRING !
  #     TEXT_KV_FROM_ARG+="\"$key\":\"$val\""
  #   done

  #   # transformed text to json
  #   TR_JSON_LINE=$(printf '{%s}' "$TEXT_KV_FROM_ARG")
  #   MERGED_JSON_LINE=$(jq -n --argjson a "$MERGED_JSON_LINE" --argjson b "$TR_JSON_LINE" '$a + $b')
  # fi
done

#
# final merge
#

printf '%s\n' "$INPUT_JSON_LINES" |
  jq -c --argjson patch "$MERGED_JSON_LINE" '. + $patch'
