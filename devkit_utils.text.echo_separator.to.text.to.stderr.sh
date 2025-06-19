#!/bin/bash

show_example() {

  echo " "
  echo "  $(basename "$0") "
  echo " "
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - echo separator lien :: YELLOW "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help]"
  echo
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

YELLOW='\033[0;33m' # yellow / no bg
NC='\033[0m'

function yellow() {
  printf '\n%b\n\n' "${YELLOW}---------------------------------------------------------------------------------------------------------------------------------------------${NC}" >&2
}

yellow "$STR_ARG"
