#!/bin/bash

showExample() {

  echo " "
  echo "  $(basename "$0") hello_world"
  echo " "
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo NAME
  echo "  $(basename "$0") - echo std WARNING message - text-color :: YELLOW "
  echo
  echo SYNOPSIS
  echo "  $(basename "$0") [-h|--help]"
  echo
  echo EXAMPLE
  echo "  $(showExample)"
  echo
  exit 1
fi

YELLOW='\033[0;33m' # yellow / no bg
NC='\033[0m'

function yellow() {

  printf ':: TRACE :: %b\n' "${YELLOW}$*${NC}" 1>&2

  # printf '%b\n' "${YELLOW}$*${NC}" 1>&2

}

if [ $# -eq 1 ]; then
  STR_ARG="$1"
  yellow "$STR_ARG"
else
  showExample
fi
