#!/bin/bash

showExample() {

  echo " "
  echo "  $(basename "$0") "
  echo " "
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then

  echo NAME
  echo "  $(basename "$0") - echo separator lien :: YELLOW "
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
  printf '\n%b\n\n' "${YELLOW}---------------------------------------------------------------------------------------------------------------------------------------------${NC}" >&2
}

yellow "$STR_ARG"
