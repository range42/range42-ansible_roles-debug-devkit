#!/bin/bash

showExample() {

  echo " "
  echo "  $(basename "$0") hello_world"
  echo " "
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo NAME
  echo "  $(basename "$0") - echo std PASS message - text-color :: GREEN "
  echo
  echo SYNOPSIS
  echo "  $(basename "$0") [-h|--help]"
  echo
  echo EXAMPLE
  echo "  $(showExample)"
  echo
  exit 1
fi

GREEN='\033[0;32m' # green / no bg
NC='\033[0m'

function green() {
  # printf '%s\n' "${GREEN}$*${NC}" 1>&2 # check
  printf ':: PASS    :: %b\n' "${GREEN}$*${NC}" 1>&2
}

if [ $# -eq 1 ]; then
  STR_ARG="$1"
  green "$STR_ARG"
else
  showExample
fi
