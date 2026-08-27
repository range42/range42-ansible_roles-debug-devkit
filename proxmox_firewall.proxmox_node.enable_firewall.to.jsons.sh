#!/bin/bash

#
# PR-59
#

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

set -euo pipefail
ACTION="firewall_node_enable"
DEFAULT_OUTPUT_JSON=true

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

show_example() {
  echo "  :: WITH VALUES FROM STDIN (as plain text) "
  echo
  echo "    echo \"px-testing\" | $(basename "$0") "
  echo "    echo \"px-testing\" | $(basename "$0") --json"
  echo "    echo \"px-testing\" | $(basename "$0") --text"
  echo
  echo "    cat /tmp/proxmox_node.text | $(basename "$0")"
  echo

  echo "  :: WITH VALUEs FROM STDIN (as JSON lines)"
  echo

  local STDIN_JSON_DATA=(
    \
    '{"proxmox_node":"px-testing"}'
  )

  for json in "${STDIN_JSON_DATA[@]}"; do
    devkit_utils.text.echo_json_helper.to.text.sh "$json"
  done | sed '$ s/$/ | '"$(basename "$0")"'/'

  printf '%s | %s\n' "$(devkit_utils.text.echo_json_helper.to.text.sh "${STDIN_JSON_DATA[-1]}")" "$(basename "$0") --json"

}

if [ "${1-}" = '-h' ] || [ "${1-}" = '--help' ]; then
  echo
  echo
  echo NAME
  echo
  echo "  $(basename "$0") - Enable node firewall - Execute the specified $ACTION action via Ansible "
  echo
  echo OPTIONS
  echo
  echo "                            $(basename "$0") [-h|--help] "
  echo "  STDIN :: [proxmox_node] | $(basename "$0") [--json]    - force output as json *default"
  echo "  STDIN :: [proxmox_node] | $(basename "$0") [--text]    - force output as text"
  echo ""
  echo EXAMPLE
  echo
  echo "$(show_example)"
  echo
  echo
  exit 1
fi

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

proxmox__inc.warmup_checks.sh
proxmox__inc.warmup_checks_stdin.sh

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####
#
# define output type
#
#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

OUTPUT_JSON="$DEFAULT_OUTPUT_JSON"

case "${1:-}" in
--json)
  OUTPUT_JSON=true
  ;;
--text)
  OUTPUT_JSON=false
  ;;
"") ;;
*)
  devkit_utils.text.echo_error.to.text.to.stderr.sh "wrong number of arguments."
  show_example
  exit 1
  ;;
esac

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

JSON_LINE_REQ=$(devkit_proxmox.STDIN.stdin_or_jsons.to.jsons.sh "STR::proxmox_node" "STR::action")

#### #### #### #### #### #### #### #### #### #### #### #### #### #### #### ####

printf '%s\n' "$JSON_LINE_REQ" | while IFS=$'\n' read -r CURRENT_JSON_LINE; do

  if [[ "$OUTPUT_JSON" == true ]]; then

    # devkit_utils.text.echo_trace.to.text.to.stderr.sh "$CURRENT_JSON_LINE"
    # exit 0

    # The shared normaliser keeps only the key named after the action, and that key is built
    # by the last task of the play. So when the play stops early nothing reaches stdout, and
    # the role's own message is discarded upstream of here : do not look for it in this file.
    _dk_rc=0
    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.jsons.sh "$ACTION" || _dk_rc=$?

    if [ "$_dk_rc" -ne 0 ]; then
      devkit_utils.text.echo_error.to.text.to.stderr.sh \
        "stopped without printing anything (rc=${_dk_rc}). This action checks that a way back in exists BEFORE it changes the firewall, so a refusal leaves the configuration as it was."
      devkit_utils.text.echo_error.to.text.to.stderr.sh \
        "run the same command with --text instead of --json : it says whether the check refused or the Proxmox could not be reached, and what to run first."
      exit "$_dk_rc"
    fi

  else

    printf '%s\n' "$CURRENT_JSON_LINE" |
      proxmox__inc.jsons.basic_vm_actions.to.text.sh "$ACTION"

  fi

done
