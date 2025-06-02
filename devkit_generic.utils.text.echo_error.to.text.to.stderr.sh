#!/bin/bash

showExample() {

  echo " "
  echo "  $(basename "$0") hello_world"
  echo " "
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo NAME
  echo "  $(basename "$0") - echo std error message - text-color :: RED "
  echo
  echo SYNOPSIS
  echo "  $(basename "$0") [-h|--help]"
  echo
  echo EXAMPLE
  echo "  $(showExample)"
  echo
  exit 1
fi

RED='\033[0;31m' # red / no bg
NC='\033[0m'

function red() {
  printf ':: ERROR   :: %b\n' "${RED}$*${NC}" 1>&2
}

if [ $# -eq 1 ]; then
  STR_ARG="$1"
  red "$STR_ARG"
else
  showExample
fi
