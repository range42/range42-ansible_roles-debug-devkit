#!/bin/bash

#
# PR-26
#

set -euo pipefail

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Warmup checks - do not edit. "
  echo
  echo OPTIONS
  echo
  echo "  $(basename "$0") [-h|--help] "
  echo
  echo

  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# check if role can be found in ANSIBLE_ROLES_PATH
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ -z "${ANSIBLE_ROLES_PATH:-}" ]]; then

  devkit_utils.text.echo_error.to.text.to.stderr.sh " ENV_ERROR :: ANSIBLE_ROLES_PATH not defined"
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# CONTEXT GUARD. The devkits read the node and the api token through the `secrets` link of
# their own directory, which `range42-context use` repoints at every switch. Two cases acted
# silently before this guard : a shell where no workspace is loaded (nothing to talk to, or the
# LAST workspace pointed by the link), and a shell whose workspace differs from the one a `use`
# in ANOTHER shell has just pointed the link to. The guard checks the CONTEXT only : it never
# restricts which vm_id or which object a devkit may address on that infrastructure.
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

if [[ -z "${RANGE42_ACTIVE_CONFIG_DIR:-}" || -z "${RANGE42_ANSIBLE_ROLES__DEVKITS_DIR:-}" || -z "${RANGE42_VAULT_PASSWORD_FILE:-}" ]]; then

  devkit_utils.text.echo_error.to.text.to.stderr.sh " ENV_ERROR :: no active range42 workspace in this shell - run : range42-context use <codename> <scenario>"
  exit 1
fi

if [[ ! -r "${RANGE42_VAULT_PASSWORD_FILE}" ]]; then

  devkit_utils.text.echo_error.to.text.to.stderr.sh " ENV_ERROR :: the vault password file of the active workspace is missing or unreadable (${RANGE42_VAULT_PASSWORD_FILE}) - run : range42-context use <codename> <scenario>"
  exit 1
fi

_r42_dk_secrets="$(readlink -f "${RANGE42_ANSIBLE_ROLES__DEVKITS_DIR%/}/secrets" 2>/dev/null || true)"
_r42_ws_secrets="$(readlink -f "${RANGE42_ACTIVE_CONFIG_DIR%/}/secrets" 2>/dev/null || true)"

if [[ -z "$_r42_dk_secrets" || -z "$_r42_ws_secrets" || "$_r42_dk_secrets" != "$_r42_ws_secrets" ]]; then

  devkit_utils.text.echo_error.to.text.to.stderr.sh " ENV_ERROR :: the devkits point to another workspace (${_r42_dk_secrets:-unresolvable link}) while this shell is on ${RANGE42_ACTIVE_CONFIG_DIR%/} - a 'range42-context use' ran in another shell since ; run it again in this one"
  exit 1
fi
