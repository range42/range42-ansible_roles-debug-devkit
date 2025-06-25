#!/bin/bash

# PR-24

show_example() {

  echo " "
  echo "  $(basename "$0") hello_world"
  echo " "
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - prepare json for helper and echo/print JSON line with color "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help]"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  exit 1
fi

print_json_helper() {

  local HELPER_JSON_DATA="$1"
  local HELPER_JSON_DATA_COLORED

  HELPER_JSON_DATA_COLORED=$(printf '%s' "$HELPER_JSON_DATA" | jq -C -c '.')

  LEFT_VERSION=$(printf "    echo '%s' " "$HELPER_JSON_DATA_COLORED")
  printf '%s \n' "$LEFT_VERSION"

}

# print_json_helper() {

#   local HELPER_JSON_DATA="$1"
#   local CURRENT_SCRIPT
#   CURRENT_SCRIPT=$(basename "$0")

#   # local HELPER_JSON_DATA_QUOTED
#   # HELPER_JSON_DATA_QUOTED=$(printf '%q' "$HELPER_JSON_DATA")

#   local HELPER_JSON_DATA_COLORED
#   HELPER_JSON_DATA_COLORED=$(printf '%s' "$HELPER_JSON_DATA" | jq -C -c '.')

#   LEFT_VERSION=$(printf "    echo '%s' | %s " "$HELPER_JSON_DATA_COLORED" "$CURRENT_SCRIPT")
#   printf '%s \n' "$LEFT_VERSION"

#   # RIGHT_VERSION=$(printf ' echo %s | %s ' "$HELPER_JSON_DATA_QUOTED" "$CURRENT_SCRIPT")
#   # LEFT_VERSION=$(printf '  echo %s | %s ' "$HELPER_JSON_DATA_COLORED" "$CURRENT_SCRIPT")
#   # printf '   %s  %s \n' "$LEFT_VERSION" "$RIGHT_VERSION"
# }

if [ $# -eq 1 ]; then

  print_json_helper "$1"
else
  show_example
fi
